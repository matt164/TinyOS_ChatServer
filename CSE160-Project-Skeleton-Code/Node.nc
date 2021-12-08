/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/socket.h"
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/chatClient.h"
#include <string.h>

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   
   uses interface flooding;
   
   uses interface neighborDisc;
   
   uses interface LSRouting;

   uses interface Transport;

   uses interface Timer<TMilli> as ReadTimer;

   uses interface Timer<TMilli> as WriteTimer;

   uses interface List<chatClient> as chatClients;
}

implementation{
   pack sendPackage;
   uint16_t seqNum, transferBytes, bytesToTransfer, sendSequence, numRead, readNum;
   char message[SOCKET_BUFFER_SIZE], replyMessage[SOCKET_BUFFER_SIZE], cmd[SOCKET_BUFFER_SIZE], cmdType[10] = {0}, whispUser[16] = {0};
   char *helloCmd, *msgCmd, *whisperCmd, *listusrCmd;
   uint16_t i, l, k, validCmd, whispSent, isChatServer = 0, isChatClient = 0;
   uint16_t j;
   uint16_t nextHop, TRANSPORT_TIME = 10000;
   uint16_t maxNodes = 24, numClients = 0, msgLength = 0;
   socket_t fd, currentSocket;
   socket_addr_t srcAddr, dstAddr;
   chatClient client;
   
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void handleCmd(char *cmd, chatClient user, uint16_t valid);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
      call neighborDisc.discInit();
      call LSRouting.LSInit();
      call Transport.initTransport();
      helloCmd = "hello";
      msgCmd = "msg";
      whisperCmd = "whisper";
      listusrCmd = "listusr";
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         call flooding.flood(myMsg, TOS_NODE_ID);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      seqNum = call flooding.nodeSeq(TOS_NODE_ID);
      nextHop = call LSRouting.getNextHop(TOS_NODE_ID, destination);
      //printf("Sending packet from %d to %d via %d\n",TOS_NODE_ID, destination, nextHop);
      makePack(&sendPackage, TOS_NODE_ID, destination, maxNodes + 1, 0, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, nextHop);
      dbg(FLOODING_CHANNEL, "Packet Sent   src: %d   seq: %d\n", TOS_NODE_ID, seqNum);
   }

   event void Transport.send(pack* package){
      seqNum = call flooding.nodeSeq(TOS_NODE_ID);
      package->seq = seqNum;
      nextHop = call LSRouting.getNextHop(TOS_NODE_ID, package->dest);
      if(nextHop < maxNodes + 1){
         //printf("Node: %d sending pack to dest: %d\n",TOS_NODE_ID, package->dest);
         call Sender.send(*package, nextHop);
      }
   }

   event void CommandHandler.printNeighbors(){
      for(i = 1; i <= maxNodes; i++){
         //printf("Node: %d\nNeighbors: ", i);
         for(j = 1; j <= maxNodes; j++){
            if(call neighborDisc.getReplies(i,j) > 0){
               //printf("%d ", j);
            }
         }
         //printf("\n\n");
      }
   }

   event void CommandHandler.printRouteTable(){
      call LSRouting.printRouteTable();
      call LSRouting.printDVTable();
   }

   event void CommandHandler.printLinkState(){
   }

   event void CommandHandler.printDistanceVector(){
   }

   event void CommandHandler.setTestServer(uint16_t port){
      fd = call Transport.socket();
      if(fd != NULL_SOCKET){
         srcAddr.port = port;
         srcAddr.addr = TOS_NODE_ID;
         if(call Transport.bind(fd, &srcAddr) == SUCCESS){
            if(call Transport.listen(fd) == SUCCESS){
               printf("server open correctly\nfd = %d\n", fd);
               dbg(TRANSPORT_CHANNEL, "Server created at node: %d  port: %d\n", TOS_NODE_ID, port);
               call ReadTimer.startPeriodic(TRANSPORT_TIME);
               currentSocket = fd;
            }
         }
      }
   }

   event void CommandHandler.setTestClient(uint16_t port, uint16_t dest, uint16_t dstPort, uint16_t transfer){
      fd = call Transport.socket();
      if(fd != NULL_SOCKET){
         srcAddr.port = port;
         srcAddr.addr = TOS_NODE_ID;
         if(call Transport.bind(fd, &srcAddr) == SUCCESS){
            dstAddr.port = dstPort;
            dstAddr.addr = dest;
            if(call Transport.connect(fd, &dstAddr) == SUCCESS){
               printf("client open correctly print: %d bytes\nfd = %d\n", transfer, fd);
               transferBytes = transfer;
               currentSocket = fd;
               dbg(TRANSPORT_CHANNEL, "Client created at node: %d  port: %d\n", TOS_NODE_ID, port);
               sendSequence = 1;
               call WriteTimer.startPeriodic(TRANSPORT_TIME);
            }
         }
      }
   }

   event void WriteTimer.fired(){
      /*if(call Transport.checkState(currentSocket) == SYN_SENT){
         printf("client not established\n");
      }*/
      if(call Transport.checkState(currentSocket) == ESTABLISHED){ 
         //printf("state established\n"); 
         if(transferBytes > 0){
            bytesToTransfer = transferBytes;
            if(transferBytes > SOCKET_BUFFER_SIZE){
               bytesToTransfer = SOCKET_BUFFER_SIZE;
            }
            //printf("Client sending packet from node: %d  socket: %d remaining: %d  with contents: ", TOS_NODE_ID, currentSocket, transferBytes);
            for(i = 0; i < bytesToTransfer; i++){
               message[i] = sendSequence;
               //printf("%d ", sendSequence);
               sendSequence++;
            }
            //printf("\n");

            bytesToTransfer = call Transport.write(currentSocket, message, bytesToTransfer);
            transferBytes -= bytesToTransfer;
         }
      }
   }

   event void ReadTimer.fired(){
      //printf("reader reading\n");
      if(isChatServer == 1){
         for(l = 0; l < numClients; ++l){
            validCmd = 0;
            client = call chatClients.popfront();
            numRead = call Transport.read(client.socket, message, SOCKET_BUFFER_SIZE);
            for(j = 0; j < numRead; ++j){
               if(message[j] == '\r' && message[j + 1] == '\n'){
                  cmd[j] = message[j];
                  cmd[j + 1] = message[j+1];
                  validCmd = 1;
                  break;
               }
               cmd[j] = message[j];
            }
            handleCmd(cmd, client, validCmd);
         }
      }
      else if(isChatClient == 1){
         numRead = call Transport.read(currentSocket, message, SOCKET_BUFFER_SIZE);
         if(numRead != 0){
            printf("Server at node: %d  read: %s", TOS_NODE_ID, message);
            /*i = 0;
            while(message[i] != '\r' && message[i + 1] != '\n'){
               if(i >= SOCKET_BUFFER_SIZE){
                  break;
               }
               printf("%c",message[i]);
               i++;
            }
            printf("\n");*/
         }
      }
      else{
         numRead = call Transport.read(currentSocket, message, SOCKET_BUFFER_SIZE);
         for(i = 0; i < numRead; i++){
            if(message[i] != 0){
               dbg(TRANSPORT_CHANNEL, "Server at node: %d  read: %d\n", TOS_NODE_ID, message[i]);
            }
         }
      }
   }

   event void CommandHandler.setAppServer(uint16_t port){
      fd = call Transport.socket();
      if(fd != NULL_SOCKET){
         srcAddr.port = port;
         srcAddr.addr = TOS_NODE_ID;
         if(call Transport.bind(fd, &srcAddr) == SUCCESS){
            if(call Transport.listen(fd) == SUCCESS){
               dbg(TRANSPORT_CHANNEL, "App server created at node: %d  port: %d\n", TOS_NODE_ID, port);
               isChatServer = 1;
               currentSocket = fd;
               call ReadTimer.startPeriodic(TRANSPORT_TIME);
            }
         }
      }
   }

   event void CommandHandler.setAppClient(uint16_t port){
      fd = call Transport.socket();
      if(fd != NULL_SOCKET){
         srcAddr.port = port;
         srcAddr.addr = TOS_NODE_ID;
         if(call Transport.bind(fd, &srcAddr) == SUCCESS){
            dstAddr.port = 41;
            dstAddr.addr = 1;
            if(call Transport.connect(fd, &dstAddr) == SUCCESS){
               dbg(TRANSPORT_CHANNEL, "Client created at node: %d  port: %d\n", TOS_NODE_ID, port);
               isChatClient = 1;
               currentSocket = fd;
               call ReadTimer.startPeriodic(5*TRANSPORT_TIME);
            }
         }
      }
   }

   event void CommandHandler.sendChatCmd(uint8_t* chatCmd){
      for(i = 0; i < SOCKET_BUFFER_SIZE; ++i){
         if(*(chatCmd + i) == '\r' && *(chatCmd + i + 1) == '\n'){
            validCmd = 1;
            i += 2;
            break;
         }
      }
      if(validCmd == 1){
         printf("node %d sending command: %s", TOS_NODE_ID, chatCmd);
         /*if(call Transport.checkState(currentSocket) == ESTABLISHED){
            printf("socket state: ESTABLISHED\n");
         }
         else{
            printf("socket state; not ESTABLISHED\n");
         }*/
         call Transport.write(currentSocket, chatCmd, i);
      }
   }

   event void Transport.addClient(socket_t serverFd){
      printf("adding new client\n");
      for(i = 0; i < 16; ++i){
         client.username[i] = 0;
      }
      client.socket = serverFd;
      call chatClients.pushback(client);
      numClients++;
   }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   void handleCmd(char *cmd, chatClient user, uint16_t valid){ //one while loop is busted
      i = 0;
      if(valid == 1){
         for(j = 0; j < 10; ++j){
            cmdType[j] = 0;
         }
         //printf("received valid cmd\n");
         while(cmd[i] != ' '){
            cmdType[i] = cmd[i];
            i++;
         }
         //printf("contents: %s", cmd);
         i++;
         if(strcmp(cmdType, helloCmd) == 0){
            j = 0;
            printf("adding username: ");
            while(cmd[i] != '\r' && cmd[i+1] != '\n'){
               if(j >= 16){
                  dbg(TRANSPORT_CHANNEL, "Max username length of 16");
                  break;
               }
               user.username[j] = cmd[i];
               printf("%c", user.username[j]);
               j++;
               i++;
            }
            printf("\n");
         }
         else if(strcmp(cmdType, msgCmd) == 0){
            for(j = 0; j < 16; ++j){
               if(user.username[j] == 0){
                  break;
               }
               replyMessage[j] = user.username[j];
            }
            replyMessage[j] = ':';
            j++;
            replyMessage[j] = ' ';
            j++;
            for(i; i < SOCKET_BUFFER_SIZE; i++){
               if(cmd[i] == '\r' && cmd[i+1] == '\n'){
                  replyMessage[j] = '\r';
                  replyMessage[j+1] = '\n';
                  j += 2;
                  break;
               }
               replyMessage[j] = cmd[i];
               j++;
            }
            msgLength = j;
            dbg(TRANSPORT_CHANNEL, "Broadcasting msg to all users\n");
            for(i = 0; i < numClients; i++){
               call Transport.write(user.socket, replyMessage, msgLength);
               call chatClients.pushback(user);
               user = call chatClients.popfront();
            }
         }
         else if(strcmp(cmdType, whisperCmd) == 0){
            j = 0;
            whispSent = 0;
            while(cmd[i] != ' '){
               whispUser[j] = cmd[i];
               i++;
               j++;
            }
            i++;
            //copy whisper to the new message
            for(j = 0; j < 8; ++j){
               replyMessage[j] = cmd[j];
            }
            //add the sender's username
            for(k = 0; k < 16; k++){
               if(user.username[k] != 0){
                  replyMessage[j] = user.username[k];
                  j++;
               }
            }
            replyMessage[j] = ':';
            j++;
            replyMessage[j] = ' ';
            j++;
            //add the rest of the whisper message
            for(j; j < SOCKET_BUFFER_SIZE; ++j){
               if(cmd[i] == '\r' && cmd[i+1] == '\n'){
                  replyMessage[j] = '\r';
                  replyMessage[j+1] = '\n';
                  j += 2;
                  break;
               }
               replyMessage[j] = cmd[i];
               i++;
            }
            msgLength = j;
            call chatClients.pushback(user);
            user = call chatClients.popfront();
            for(j = 0; j < numClients - 1; ++j){
               if(strcmp(whispUser, user.username) == 0){
                  call Transport.write(user.socket, replyMessage, msgLength);
                  whispSent = 1;
               }
               call chatClients.pushback(user);
               user = call chatClients.popfront();
            }

            if(whispSent == 0){
               dbg(TRANSPORT_CHANNEL, "User: %s not found\n", whispUser);
            }
         }
         else if(strcmp(cmdType, listusrCmd) == 0){
            replyMessage[0] = 'u';
            replyMessage[1] = 's';
            replyMessage[2] = 'e';
            replyMessage[3] = 'r';
            replyMessage[4] = 's';
            replyMessage[5] = ':';
            replyMessage[6] = ' ';
            k = 7;
            for(j = 0; j < numClients; ++j){
               for(i = 0; i < 16; ++i){
                  if(user.username[i] == 0){
                     break;
                  }
                  replyMessage[k] = user.username[i];
                  k++;
               }
               replyMessage[k] = ' ';
               k++;
               call chatClients.pushback(user);
               user = call chatClients.popfront();
            }
            replyMessage[k] = '\r';
            k++;
            replyMessage[k] = '\n';
            k++;
            call Transport.write(user.socket, replyMessage, k);
         }
      }
     call chatClients.pushback(user);
   }

}
