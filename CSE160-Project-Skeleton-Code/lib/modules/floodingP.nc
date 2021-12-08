#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module floodingP{
	provides interface flooding;

	uses interface SimpleSend as Sender;
	
	uses interface neighborDisc;
	
	uses interface LSRouting;

	uses interface Transport;
}

implementation{
	
	//node table to hold the highest seq num flood packet recieved by each node in the network from each flood source
	//first dimmension is the owner of that corresponding array of data
	//second dimmension corresponds to the node ID of the flood src and stores the highest recieved seq
	//nodeTable[i][i] corresponds to the sequence number of a given node i
	uint16_t maxNodes = 24;
	uint16_t nodeTable[24][24] = {0};
	uint16_t nextHop;

	//passed in a msg to forward and the ID of the node that is to flood it.
	command void flooding.flood(pack *msg, uint16_t curNodeID){
		if(msg->seq > nodeTable[curNodeID - 1][msg->src - 1]){  //if seq of recieved higher than stored new flood so forward
			nodeTable[curNodeID - 1][msg->src - 1] = msg->seq;					//store the seq of the new most recent flood in the node table
			//Setting the destination to a non-existing node means that the message is meant to flood the whole network
			if(msg->dest > maxNodes){
				//if the message to be flooded is a Link State packet update this node's distance vector table
				if(msg->protocol == 2){
					call LSRouting.updateNeighbors(msg, curNodeID);
				}
				//if the TTL of the flood is not yet 0 forward an updated packet to all neighbors
				if(msg->TTL - 1 > 0){                                   
					dbg(FLOODING_CHANNEL, "Ping received   node: %d   src: %d\n",curNodeID,msg->src);
					msg->TTL = msg->TTL - 1;
					call Sender.send(*msg, AM_BROADCAST_ADDR);
					dbg(FLOODING_CHANNEL, "Ping sent   node: %d\n", curNodeID);
				}
				else{
					//the message was a neighbor discovery request
					if(msg->protocol == 6){
						call neighborDisc.receiveRequest(msg, curNodeID);
					}
				}
			}
			else{
				//the message you received was a reply to a neighbor discovery request
				if(msg->protocol == 7){  
					call neighborDisc.receiveReply(msg, curNodeID);
				}
				//the message was a normal ping and should be sent along the global shortest path via the routing table
				if(msg->dest != curNodeID){
					nextHop = call LSRouting.getNextHop(curNodeID, msg->dest);
					//printf("Sending packet from %d to %d via %d\n",msg->src, msg->dest, nextHop);
					call Sender.send(*msg, nextHop);
				}
				else{
					if(msg->protocol == PROTOCOL_TCP){
						//printf("TCP packet received\n");
						call Transport.receive(msg);
					}
				}
			}
		}
	}

	event void Transport.send(pack* package){}
	event void Transport.addClient(socket_t serverFd){}

	//passed in a node id increments the seq number stored for that node and returns it, for use when a node makes the initial ping that triggers a flood 
	command uint16_t flooding.nodeSeq(uint16_t nodeID){
		nodeTable[nodeID-1][nodeID-1] = nodeTable[nodeID-1][nodeID-1] + 1;
		return nodeTable[nodeID-1][nodeID-1];
	}

}
