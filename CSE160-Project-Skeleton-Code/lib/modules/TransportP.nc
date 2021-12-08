#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include <stdlib.h>

module TransportP{
	provides interface Transport;

	//used to manage the sliding window
	uses interface List<pack> as waitingForAck;
	uses interface List<uint32_t> as resendAt;
	uses interface List<socket_t> as socketList;
	uses interface Timer<TMilli> as resendTimer;
}

implementation{
	typedef struct TCPpack{
		uint8_t srcPort;
		uint8_t destPort;
		uint16_t Seq;
		uint16_t Ack;
		uint8_t flags;                  //3 lowest bits are treated as FIN ACK and SYN flags repectively ie: 1 = SYN_FLAG, 2 = ACK_FLAG and 4 = FIN_FLAG, multiple flags are the sum of the respective flags
		uint8_t advertisedWindow;
		uint8_t buffer[TCP_MAX_PAYLOAD_SIZE];
	} TCPpack;


	socket_store_t sockets[MAX_NUM_OF_SOCKETS];
	uint8_t i, j, sendSeq, rcvdPos, advWindow, numPacks, sendDone, readPos;
	socket_t sock, rcvdSock, advSock, lSock = 0;
	error_t error;
	socket_addr_t addr;
	TCPpack rcvdTCP, replyTCP, outTCP;
	pack sendPack, outPack;
	uint16_t buffLen, bytesWritten, bytesRead;
	uint32_t time, time1, time2;

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
	void makeTCPpack(TCPpack *packet, uint8_t srcPort, uint8_t destPort, uint16_t Seq, uint16_t Ack, uint8_t flags, uint8_t advertisedWindow, uint8_t *buffer, uint8_t length);
	void createOutstanding(pack Package, uint16_t timeout, socket_t fd);
	uint16_t incSeq(uint16_t seq, uint8_t inc);
	uint16_t decSeq(uint16_t seq, uint8_t dec);
	uint8_t sendFromBuff(socket_t fd, uint8_t advWindow);
	void receivePack(socket_t rcvdSock, TCPpack* packet);
	void advanceWindow(socket_t advSock, pack *rcvdPack);
	socket_t findFd(uint8_t port, uint16_t addr);
	void logTCPpack(pack *packet, socket_t fd);

	command socket_t Transport.socket(){
		for(i = 1; i < MAX_NUM_OF_SOCKETS; ++i){
			if(sockets[i].state == CLOSED){
				return i;
			}
		}
		return NULL_SOCKET;
	}

	command void Transport.initTransport(){
		for(i = 0; i < MAX_NUM_OF_SOCKETS; ++i){
			sockets[i].state = CLOSED;
			sockets[i].sendSpace = SOCKET_BUFFER_SIZE;
			sockets[i].rcvdSpace = SOCKET_BUFFER_SIZE;
			lSock = 0;
		}
	}

	command enum socket_state Transport.checkState(socket_t fd){
		return sockets[fd].state;
	}

	command error_t Transport.bind(socket_t fd, socket_addr_t *addr){
		if(fd != NULL_SOCKET && addr != NULL){	
			sockets[fd].src = addr->port;
			sockets[fd].dest.addr = 0;
			sockets[fd].dest.port = 0;
			sockets[fd].sendSpace = SOCKET_BUFFER_SIZE;
			sockets[fd].rcvdSpace = SOCKET_BUFFER_SIZE;
			for(i = 0; i < SOCKET_BUFFER_SIZE; ++i){
				sockets[fd].sendBuff[i] = 0;
				sockets[fd].rcvdBuff[i] = 0; 
			}
			sockets[fd].RTT = CONSERVATIVE_RTT;
			sockets[fd].lastWritten = 0;
    		sockets[fd].lastAck = 0;
    		sockets[fd].lastSent = 0;
    		sockets[fd].lastRead = 0;
    		sockets[fd].lastRcvd = 0;
    		sockets[fd].nextExpected = 0;
    		sockets[fd].effectiveWindow = 0;
			call resendTimer.startOneShotAt(call resendTimer.getNow(), CONSERVATIVE_RTT);
			return SUCCESS;

		}
		return FAIL;
	}

	command socket_t Transport.accept(socket_t fd, socket_port_t port){
		addr.port = port;
		addr.addr = TOS_NODE_ID;
		error = call Transport.bind(fd,&addr);
		sockets[fd].lastAck = decSeq(sockets[fd].lastAck, 1);
		if(error == SUCCESS)
			return fd;
		return NULL_SOCKET;
	}

	command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
		bytesWritten = 0;
		//printf("fd: %d\n",fd);
		if(fd != NULL_SOCKET && sockets[fd].state == ESTABLISHED){	
			for(i = 0; i < bufflen; ++i){
				if(sockets[fd].sendSpace < 3){
					break;
				}
				sockets[fd].lastWritten = incSeq(sockets[fd].lastWritten, 1);
				sockets[fd].sendBuff[sockets[fd].lastWritten] = buff[i];
				sockets[fd].sendSpace--;
				bytesWritten++;
				//printf("writing to buffer\n");
			}
		}
		i = sendFromBuff(fd, SOCKET_BUFFER_SIZE);
		return bytesWritten;
	}

	command error_t Transport.receive(pack* package){
		if(package->protocol == PROTOCOL_TCP){
			memcpy(&rcvdTCP, package->payload, PACKET_MAX_PAYLOAD_SIZE);
			sock = findFd(rcvdTCP.srcPort, package->src);
			//logTCPpack(package, sock);
			if(rcvdTCP.flags == SYN_FLAG){
					if(lSock != 0 && sockets[lSock].state == LISTEN){
						for(i = 1; i < MAX_NUM_OF_SOCKETS; ++i){
							if(sockets[i].dest.addr == package->src && sockets[i].dest.port == rcvdTCP.srcPort){
								return FAIL;
							}
						}
						if(call Transport.accept(lSock, rcvdTCP.destPort) != NULL_SOCKET){
							sockets[lSock].dest.addr = package->src;
							sockets[lSock].dest.port = rcvdTCP.srcPort;
							sockets[lSock].lastRead = rcvdTCP.Seq;
							sockets[lSock].lastRcvd = sockets[lSock].lastRead;
							sockets[lSock].nextExpected = incSeq(sockets[lSock].lastRead, 1);
							if(sockets[lSock].src == 41){
								signal Transport.addClient(lSock);
							}
							makeTCPpack(&replyTCP, sockets[lSock].src, sockets[lSock].dest.port, 0, sockets[lSock].nextExpected, SYN_FLAG + ACK_FLAG, SOCKET_BUFFER_SIZE, "", TCP_MAX_PAYLOAD_SIZE);	
							makePack(&sendPack, TOS_NODE_ID, sockets[lSock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
							memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);

							signal Transport.send(&sendPack);
							createOutstanding(sendPack, CONSERVATIVE_RTT, lSock);
							sockets[lSock].state = SYN_RCVD;
							i = call Transport.socket();
							call Transport.listen(i);
							return SUCCESS;				 
						}
					}
				}
			else if(sock != NULL_SOCKET){
				if(sockets[sock].state == ESTABLISHED){
					if((rcvdTCP.flags & SYN_FLAG) == 0){  //SYN_FLAG not set
						if(rcvdTCP.flags == ACK_FLAG){
							//advance sliding window for acked packets in the send buffer
							advanceWindow(sock, package);

							/*printf("sendbuff contents: ");
							for(i = 0 ; i < SOCKET_BUFFER_SIZE; i++){
								printf("%d ", sockets[sock].sendBuff[i]);
							}*/
							//send up to the received advertised window bytes of data
							sendFromBuff(sock, rcvdTCP.advertisedWindow);
							return SUCCESS;
						}
						else if(rcvdTCP.flags == NO_FLAG){  //Client sends data to server with no flag
							//advance sliding window for receive buffer
							receivePack(sock, &rcvdTCP);

							//calculate advertised window to give to sender
							advWindow = SOCKET_BUFFER_SIZE - (sockets[sock].nextExpected - 1 - sockets[sock].lastRead);

							//create an ack packet to send back to the client
							makeTCPpack(&replyTCP, sockets[sock].src, sockets[sock].dest.port, sockets[sock].lastSent, sockets[sock].nextExpected, ACK_FLAG, advWindow, "", TCP_MAX_PAYLOAD_SIZE);
							makePack(&sendPack, TOS_NODE_ID, sockets[sock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
							memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);

							//send the packet
							signal Transport.send(&sendPack);

							/*for(i = 0 ; i < SOCKET_BUFFER_SIZE; i++){
								printf("%d ", sockets[sock].rcvdBuff[i]);
							}*/

							//not sending any data with my ACK so I don't have anything to ack
							//createOutstanding(sendPack, CONSERVATIVE_RTT);
							return SUCCESS;
						}
						else if(rcvdTCP.flags == FIN_FLAG){ //currently 1 sided close initiated by client
							//make fin and ack packet to send back to the client in FIN_WAIT
							makeTCPpack(&replyTCP, sockets[sock].src, sockets[sock].dest.port, sockets[sock].lastSent, sockets[sock].nextExpected,FIN_FLAG + ACK_FLAG, 0, "",TCP_MAX_PAYLOAD_SIZE);
							makePack(&sendPack, TOS_NODE_ID, sockets[sock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
							memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);

							//send the packet and place this socket into FIN_WAIT
							signal Transport.send(&sendPack);
							sockets[sock].state = FIN_WAIT;
							createOutstanding(sendPack, CONSERVATIVE_RTT, sock);
							return SUCCESS;
						}
					}
				}
				else if(sockets[sock].state == SYN_SENT){
					if(rcvdTCP.flags == SYN_FLAG + ACK_FLAG){
						sockets[sock].lastAck = decSeq(rcvdTCP.Ack, 1);
						sendSeq = incSeq(sockets[sock].lastSent, 1);

						makeTCPpack(&replyTCP, sockets[sock].src, sockets[sock].dest.port, sendSeq, 1, ACK_FLAG, SOCKET_BUFFER_SIZE, "", TCP_MAX_PAYLOAD_SIZE);   
						makePack(&sendPack, TOS_NODE_ID, sockets[sock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
						memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);
						
						signal Transport.send(&sendPack);
						advanceWindow(sock, package);
						createOutstanding(sendPack, CONSERVATIVE_RTT, sock);
						sockets[sock].state = ESTABLISHED;
						sockets[sock].lastWritten = sendSeq;
						sockets[sock].lastSent = sendSeq;
						sockets[sock].sendSpace --;
						return SUCCESS;						
					}
				}
				else if(sockets[sock].state == SYN_RCVD){
					if(rcvdTCP.flags == ACK_FLAG){
						sockets[sock].lastRcvd = rcvdTCP.Seq;
						sockets[sock].lastRead = rcvdTCP.Seq;
						sockets[sock].nextExpected = incSeq(rcvdTCP.Seq, 1);
						sockets[sock].state = ESTABLISHED;
						
						advanceWindow(sock, package);
						//makeTCPpack(&replyTCP, sockets[sock].src, sockets[sock].dest.port, 1, sockets[sock].nextExpected, ACK_FLAG, SOCKET_BUFFER_SIZE, "", TCP_MAX_PAYLOAD_SIZE);
						//makePack(&sendPack, TOS_NODE_ID, sockets[sock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
						//memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);

						//signal Transport.send(&sendPack);
						//createOutstanding(sendPack, CONSERVATIVE_RTT);
						return SUCCESS;
					}
				}
				else if(sockets[sock].state == FIN_WAIT){
					sockets[sock].lastRcvd = rcvdTCP.Seq;
					sockets[sock].nextExpected = incSeq(sockets[sock].lastRcvd,1);
					if(rcvdTCP.flags == FIN_FLAG + ACK_FLAG){
						advanceWindow(sock, package);
						sockets[sock].lastSent = incSeq(sockets[sock].lastSent,1);
						makeTCPpack(&replyTCP, sockets[sock].src, sockets[sock].dest.port, sockets[sock].lastSent, sockets[sock].nextExpected,FIN_FLAG + ACK_FLAG, 0, "",TCP_MAX_PAYLOAD_SIZE);
						makePack(&sendPack, TOS_NODE_ID, sockets[sock].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
						memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);
						signal Transport.send(&sendPack);
						sockets[sock].state = TIME_WAIT;
						createOutstanding(sendPack, CONSERVATIVE_RTT, sock);

						//should wait a long time ~2 * max RTT but won't now for convinience

						sockets[sock].state = CLOSED;
						return SUCCESS;
					}
				}
			}
		}
		return FAIL;	
	}

	command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
		bytesRead = 0;
		if(fd != NULL_SOCKET && sockets[fd].state == ESTABLISHED && sockets[fd].lastRead != sockets[fd].lastRcvd){
			/*printf("node %d rcvdBuff contents: ", TOS_NODE_ID);
			for(i = 0; i < SOCKET_BUFFER_SIZE; ++i){
				printf("%d ", sockets[fd].rcvdBuff[i]);
			}
			printf("\n");*/
			for(i = 0; i < bufflen; ++i){
				readPos = incSeq(sockets[fd].lastRead,1);
				if(sockets[fd].rcvdBuff[readPos] != 0){
					buff[i] = sockets[fd].rcvdBuff[readPos];
					bytesRead++;
					sockets[fd].rcvdBuff[readPos] = 0;
					sockets[fd].lastRead = readPos;
				}
				else{
					break;
				}
			}
			//printf("lastRead: %d  lastRcvd: %d  bytesRead: %d\n", sockets[fd].lastRead, sockets[fd].lastRcvd, bytesRead);
		}
		return bytesRead;
	}

	command error_t Transport.connect(socket_t fd, socket_addr_t *addr){
		if(fd != NULL_SOCKET){
			if(sockets[fd].state == CLOSED){
				//printf("connecting ");
				sockets[fd].dest = *addr;
				//printf("fd: %d dest addr: %d  dest port: %d\n",fd, sockets[fd].dest.addr,sockets[fd].dest.port);
				sockets[fd].lastSent = 0;
				sockets[fd].lastAck = decSeq(sockets[fd].lastSent,1);
				sockets[fd].lastWritten = 0;
				sockets[fd].sendSpace = SOCKET_BUFFER_SIZE - 1;
				sockets[fd].rcvdSpace = SOCKET_BUFFER_SIZE;

	    		makeTCPpack(&replyTCP, sockets[fd].src, sockets[fd].dest.port, 0, 0, SYN_FLAG, SOCKET_BUFFER_SIZE, "", TCP_MAX_PAYLOAD_SIZE);
	    		makePack(&sendPack, TOS_NODE_ID, sockets[fd].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
				memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);
				//logTCPpack(&sendPack, fd);
				signal Transport.send(&sendPack);
				createOutstanding(sendPack, CONSERVATIVE_RTT, sock);
				sockets[fd].state = SYN_SENT;
				return SUCCESS;
			}
		}
		return FAIL;
	}

	command error_t Transport.close(socket_t fd){
		if(fd != NULL_SOCKET && sockets[fd].state == ESTABLISHED){
			sendSeq = incSeq(sockets[fd].lastSent, 1);
			makeTCPpack(&replyTCP, sockets[fd].src, sockets[fd].dest.port, sendSeq, sockets[fd].nextExpected, FIN_FLAG, 0, "", TCP_MAX_PAYLOAD_SIZE);
			makePack(&sendPack, TOS_NODE_ID, sockets[fd].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
			memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);
			signal Transport.send(&sendPack);
			sockets[fd].state = FIN_WAIT;
			createOutstanding(sendPack, CONSERVATIVE_RTT, sock);
			return SUCCESS;
		}
		return FAIL;
	}

	command error_t Transport.release(socket_t fd){

	}

	command error_t Transport.listen(socket_t fd){
		if(fd != NULL_SOCKET && sockets[fd].state == CLOSED){
			sockets[fd].state = LISTEN;
			lSock = fd;
			//printf("socket: %d  state: LISTEN\n", fd);
			return SUCCESS;
		}
		return FAIL;
	}

	socket_t findFd(uint8_t port, uint16_t addr){
		//printf("node: %d  port: %d  addr: %d\n", TOS_NODE_ID ,port, addr);
		for(i = 1; i < MAX_NUM_OF_SOCKETS; i++){
			//printf("i: %d  port: %d  addr: %d\n", i, sockets[i].dest.port, sockets[i].dest.addr);
			if(sockets[i].dest.port == port && sockets[i].dest.addr == addr){
				return i;
			}
		}
		return 0;
	} 

	event void resendTimer.fired(){
		time = call resendTimer.getNow();
		if(call waitingForAck.isEmpty()){
			call resendTimer.startOneShotAt(time, CONSERVATIVE_RTT);
			return;
		}

		time1 = call resendAt.front();

		if(time < time1){
			call resendTimer.startOneShotAt(time, 1 + time - time1);
			return;
		}

		outPack = call waitingForAck.popfront();
		time1 = call resendAt.popfront();
		sock = call socketList.popfront();
		memcpy(&outTCP, &outPack.payload, PACKET_MAX_PAYLOAD_SIZE);
		if(sockets[sock].lastSent >= sockets[sock].lastAck){  //typical case
			if(decSeq(outTCP.Seq,1) <= sockets[sock].lastAck || decSeq(outTCP.Seq,1) > sockets[sock].lastSent){
				call resendTimer.startOneShotAt(time, CONSERVATIVE_RTT);
				return;
			}
		}
		else{    //wraparound case
			if(decSeq(outTCP.Seq,1) <= sockets[sock].lastAck && decSeq(outTCP.Seq,1) > sockets[sock].lastSent){
				call resendTimer.startOneShotAt(time, CONSERVATIVE_RTT);
				return;
			}
		}

		//printf("spurrious resend\n");
		//logTCPpack(&outPack, 1);
		signal Transport.send(&outPack);

		call waitingForAck.pushback(outPack);
		call resendAt.pushback(time + CONSERVATIVE_RTT);

		if(call waitingForAck.isEmpty()){
			time2 = time + CONSERVATIVE_RTT;
		}
		else{
			time2 = call resendAt.front();
		}

		call resendTimer.startOneShotAt(time, time2 - time);
	}

	void createOutstanding(pack Package, uint16_t timeout, socket_t fd){
		time = call resendTimer.getNow();
		call waitingForAck.pushback(Package);
		call resendAt.pushback(time + timeout);
		call socketList.pushback(fd);
		call resendTimer.startOneShotAt(time, timeout);
	}

	void advanceWindow(socket_t sock, pack *rcvdPack){
		memcpy(&rcvdTCP, &rcvdPack->payload, PACKET_MAX_PAYLOAD_SIZE);
		if((rcvdTCP.flags & ACK_FLAG) != 0){       //ACK flag is set
			//checks if the ACK received is within the sequence waiting to be ACKd
			if(sockets[sock].lastSent >= sockets[sock].lastAck){  //typical case
				if(decSeq(rcvdTCP.Ack,1) <= sockets[sock].lastAck || decSeq(rcvdTCP.Ack,1) > sockets[sock].lastSent){
					return;
				}
			}
			else{    //wraparound case
				if(decSeq(rcvdTCP.Ack,1) <= sockets[sock].lastAck && decSeq(rcvdTCP.Ack,1) > sockets[sock].lastSent){
					return;
				}
			}

			rcvdPos = incSeq(sockets[sock].lastAck,1);
			while(rcvdPos != rcvdTCP.Ack){
				sockets[sock].sendBuff[rcvdPos] = 0;
				sockets[sock].sendSpace++;
				sockets[sock].lastAck = rcvdPos;
				rcvdPos = incSeq(rcvdPos,1);
			}

			for(i = 0; i < call waitingForAck.size(); ++i){
				outPack = call waitingForAck.popfront();
				time = call resendAt.popfront();
				sock = call socketList.popfront();
				if((outPack.src == rcvdPack->dest) && (outPack.dest == rcvdPack->src)){
					memcpy(&outTCP, &outPack.payload, PACKET_MAX_PAYLOAD_SIZE);
					if(outTCP.srcPort == rcvdTCP.destPort && outTCP.destPort == rcvdTCP.srcPort){
						if(sockets[sock].lastSent >= sockets[sock].lastAck){
							if(rcvdTCP.Seq <= sockets[sock].lastAck || rcvdTCP.Seq > sockets[sock].lastSent){
								continue;
							}
						}
						else{
							if(rcvdTCP.Seq <= sockets[sock].lastAck && rcvdTCP.Seq > sockets[sock].lastSent){
								continue;
							}
						}
					}
				}
				call waitingForAck.pushback(outPack);
				call resendAt.pushback(time);
				call socketList.pushback(sock);
			}

		}
	}

	uint16_t incSeq(uint16_t seq, uint8_t inc){
		return (seq + inc) % SOCKET_BUFFER_SIZE; 
	}
	
	uint16_t decSeq(uint16_t seq, uint8_t dec){
		if(seq > dec){
			return seq - dec;
		}
		else{
			return (seq + SOCKET_BUFFER_SIZE - dec) % SOCKET_BUFFER_SIZE;
		}
	}

	/*
	Side: Server
	Writes data from a sent TCP packet to the local received buffer modifying the sliding
	window variables depending on the state. Completes when the receive buffer is full or
	you reach the end of the data in the packet.
	Arguments: sock - file descriptor corresponding to the active server socket
			   packet - the TCP packet received by the server
	*/
	void receivePack(socket_t rcvdSock, TCPpack* packet){
		for(i = 0; i < TCP_MAX_PAYLOAD_SIZE; ++i){
			if(packet->buffer[i] == 0){  
				//reached the end of the data in the buffer               
				break;
			}

			//location of the current byte in the data stream
			rcvdPos = incSeq(packet->Seq, i);
			
			if(sockets[rcvdSock].lastRead <= sockets[rcvdSock].lastRcvd){               //Wraparound Case
				if(rcvdPos > sockets[rcvdSock].lastRcvd || rcvdPos <= sockets[rcvdSock].lastRead){
					sockets[rcvdSock].rcvdBuff[rcvdPos] = packet->buffer[i];
					sockets[rcvdSock].rcvdSpace --;
					sockets[rcvdSock].lastRcvd = rcvdPos;
				}
			}
			else if(sockets[rcvdSock].lastRead > sockets[rcvdSock].lastRcvd){          //Typical Case
				if(rcvdPos > sockets[rcvdSock].lastRcvd && rcvdPos <= sockets[rcvdSock].lastRead){
					sockets[rcvdSock].rcvdBuff[rcvdPos] = packet->buffer[i];
					sockets[rcvdSock].rcvdSpace --;
					sockets[rcvdSock].lastRcvd = rcvdPos;
				}
			}
			if(sockets[rcvdSock].lastRcvd != sockets[rcvdSock].lastRead){
				while(sockets[rcvdSock].rcvdBuff[sockets[rcvdSock].nextExpected] != 0){
					sockets[rcvdSock].nextExpected = incSeq(sockets[rcvdSock].nextExpected, 1);
				}
			}
		}	
	}

	/*
	Side: Client/Server
	Upon receiving a packet with an ACK sends up to the sent Advertised window bytes of dataincluding data 
	in transit to not overload the server. Calculates the effective window based on the stateof the send 
	buffer then creates and sends packets to transmit that amount of data. Stops when transmits the 
	advertised window's worth or runs out of data from the send buffer. Returns the number of packets sent
	Arguments: sock - file descriptor corresponding to the active client socket

			   advWindow - the advertised window from the server
	Return: numPacks -  number of packets data was sent in
	*/
	uint8_t sendFromBuff(socket_t fd, uint8_t advWindow){         
		numPacks = 0;
		if(sockets[fd].lastSent >= sockets[fd].lastAck){  						//Typical and Full buffer Cases
			if(advWindow > (sockets[fd].lastSent - sockets[fd].lastAck)){
				sockets[fd].effectiveWindow = advWindow - (sockets[fd].lastSent - sockets[fd].lastAck);
			}
			else{
				sockets[fd].effectiveWindow = 0;
			}
		}
		else{			//Wraparound Case
			if(advWindow > SOCKET_BUFFER_SIZE - (sockets[fd].lastAck - sockets[fd].lastSent)){       								            
				sockets[fd].effectiveWindow = advWindow - (SOCKET_BUFFER_SIZE - (sockets[fd].lastAck - sockets[fd].lastSent));
			}
			else{
				sockets[fd].effectiveWindow = 0;
			}
		}
		//advWindow = SOCKET_BUFFER_SIZE - (sockets[fd].nextExpected - 1 - sockets[fd].lastRead);  
		sendDone = 0;
		if(sockets[fd].sendBuff[incSeq(sockets[fd].lastSent, 1)] != 0){
			for(i = 0; i < sockets[fd].effectiveWindow; i += TCP_MAX_PAYLOAD_SIZE){    //sends up to effectiveWindow bytes in i = eff.window/TCP_MAX_PAYLOAD_SIZE iterations of the outer loop packets
				sendSeq = incSeq(sockets[fd].lastSent, 1);
				if(sockets[fd].sendBuff[sendSeq] == 0){
					break;
				}
				makeTCPpack(&replyTCP, sockets[fd].src, sockets[fd].dest.port, sendSeq, sockets[fd].nextExpected, NO_FLAG, advWindow, "", TCP_MAX_PAYLOAD_SIZE);

				for(j = 0; j < TCP_MAX_PAYLOAD_SIZE; ++j){
					//if you reach the end of the written data or write effectiveWindow bytes send the last packet then break
					if(sockets[fd].sendBuff[sendSeq] == 0 || i + j + 1 > sockets[fd].effectiveWindow){
						sendDone = 1;
						break;
					}
					replyTCP.buffer[j] = sockets[fd].sendBuff[sendSeq];
					sockets[fd].lastSent = sendSeq;
					sendSeq = incSeq(sendSeq, 1);
				}

				//if you reached the end for either case fill the rest of that packet's buffer with 0s
				for(; j < TCP_MAX_PAYLOAD_SIZE; ++j){
					replyTCP.buffer[j] = 0;
				}

				numPacks++;
				makePack(&sendPack, TOS_NODE_ID, sockets[fd].dest.addr, 20, PROTOCOL_TCP, 0, "", PACKET_MAX_PAYLOAD_SIZE);
				memcpy(&sendPack.payload, &replyTCP, PACKET_MAX_PAYLOAD_SIZE);
				signal Transport.send(&sendPack);
				createOutstanding(sendPack, CONSERVATIVE_RTT, fd);

				if(sendDone == 1){
					break;
				}
			}
		}

		return numPacks;

	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}

	void makeTCPpack(TCPpack *packet, uint8_t srcPort, uint8_t destPort, uint16_t Seq, uint16_t Ack, uint8_t flags, uint8_t advertisedWindow, uint8_t *buffer, uint8_t length){
		packet->srcPort = srcPort;
		packet->destPort = destPort;
		packet->Seq = Seq;
		packet->Ack = Ack;
		packet->flags = flags;
		packet->advertisedWindow = advertisedWindow;
		memcpy(packet->buffer, buffer, length);
	}

	void logTCPpack(pack *packet, socket_t fd){
		memcpy(&rcvdTCP, packet->payload, PACKET_MAX_PAYLOAD_SIZE);
		printf("packet: src %d dest %d \n",packet->src, packet->dest);
		printf("node = %d socket = %d\n",TOS_NODE_ID,fd);
		if(sockets[fd].state == SYN_SENT){
			printf("state: SYN_SENT\n");
		}
		if(sockets[fd].state == LISTEN){
			printf("state: LISTEN\n");
		}
		if(sockets[fd].state == SYN_RCVD){
			printf("state: SYN_RCVD\n");
		}
		if(sockets[fd].state == ESTABLISHED){
			printf("state: ESTABLISHED\n");
		}
		if(sockets[fd].state == FIN_WAIT){
			printf("state: SYN_SENT\n");
		}
		printf("Pack contents:  src: %d, dst: %d, seq: %d, ack: %d, flags: %d, advertisedWindow: %d\n", rcvdTCP.srcPort, rcvdTCP.destPort, rcvdTCP.Seq, rcvdTCP.Ack, rcvdTCP.flags, rcvdTCP.advertisedWindow);
		printf("Socket state: lastWritten: %d lastAck: %d lastSent: %d lastRead: %d lastRcvd: %d nextExpected: %d\n", sockets[fd].lastWritten, sockets[fd].lastAck, sockets[fd].lastSent, sockets[fd].lastRead, sockets[fd].lastRcvd, sockets[fd].nextExpected);
		printf("packet buffer contents: ");
		for(i = 0; i < TCP_MAX_PAYLOAD_SIZE; i++){
			printf("%d ",rcvdTCP.buffer[i]);
		}
		printf("\n");
	}

}