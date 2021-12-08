#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module LSRoutingP{
	provides interface LSRouting;

	uses interface SimpleSend as Sender;

	uses interface Timer<TMilli> as LSTimer;
}

implementation{
	
	uint16_t maxNodes = 19;
	uint16_t i, j, k, min, minIndex, v, nextHop, dist;
	bool considered[19] = {0};	

	//first dimmension is the node who owns that particular routing table
	//second dimmension is the node to which you wish to route
	//first element of third dimmension is next hop, second is path cost currently using hop count, third element is the highest seq number LS packet received 4th is counter to time out stale data
	uint16_t routingTable[19][19][4] = {0};

	//first dimmension is the owner of that Distance Vector Table
	//second dimmension is the source node of the Link State Announcement
	//third dimmension is the distances to each node from that node
	uint16_t DVTable[19][19][19] = {0};

	uint16_t minNode(uint16_t curNodeID);
	void calculatePaths(uint16_t curNodeID);

	void calculatePaths(uint16_t curNodeID){
		//call LSRouting.printDVTable();
		for(i = 0; i < maxNodes; i++){
			routingTable[curNodeID - 1][i][0] = maxNodes + 1;
			routingTable[curNodeID - 1][i][1] = maxNodes + 1;
			routingTable[curNodeID - 1][i][3] = routingTable[curNodeID - 1][i][3] - 1;
			//times out stale data after 2 cycles of not being updated.
			if(routingTable[curNodeID - 1][i][3] < 1)
				for(j = 0; j < maxNodes; j++)
					DVTable[curNodeID - 1][i][j] = maxNodes + 1;
			considered[i] = 0;
		}
		routingTable[curNodeID - 1][curNodeID - 1][1] = 0;

		for(i = 0; i < maxNodes - 1; i++){

			v = minNode(curNodeID);
			considered[v] = 1;

			for(j = 0; j < maxNodes; j++){

				if(!considered[j] && DVTable[curNodeID - 1][v][j] < maxNodes + 1 && routingTable[curNodeID - 1][v][1] + DVTable[curNodeID - 1][v][j] < routingTable[curNodeID - 1][j][1]){

					routingTable[curNodeID - 1][j][1] = routingTable[curNodeID - 1][v][1] + DVTable[curNodeID - 1][v][j];
					if(v == curNodeID - 1)
						routingTable[curNodeID - 1][j][0] = j + 1;
					else
						routingTable[curNodeID - 1][j][0] = routingTable[curNodeID - 1][v][0]; 
				}
			}
		}
		dbg(ROUTING_CHANNEL, "Updating Routing table for node %d\n", TOS_NODE_ID);
	}

	command void LSRouting.LSInit(){
		call LSTimer.startPeriodic(60000);
	}

	command void LSRouting.updateNeighbors(pack *msg, uint16_t curNodeID){
		if(msg->seq > routingTable[curNodeID - 1][msg->src - 1][2]){
			dbg(ROUTING_CHANNEL, "Node %d received DV  src: %d", TOS_NODE_ID, msg->src);
			routingTable[curNodeID - 1][msg->src - 1][2] = msg->seq;
			for(i = 0; i < maxNodes; i++){
				DVTable[curNodeID - 1][msg->src - 1][i] = *(msg->payload + i);
				//sets the timer for stale data to 3
				routingTable[curNodeID - 1][msg->src - 1][3] = 3;
			}
		}
	}

	command uint16_t LSRouting.getNextHop(uint16_t curNodeID, uint16_t destNodeID){
		return routingTable[curNodeID - 1][destNodeID - 1][0];
	}
	
	command void LSRouting.printRouteTable(){
		printf("Routing Table of Node: %d\n",TOS_NODE_ID);
		for(i = 0; i < maxNodes; i++){
			//if( i + 1 != TOS_NODE_ID && routingTable[TOS_NODE_ID - 1][i][1] < maxNodes + 1){
				nextHop = routingTable[TOS_NODE_ID - 1][i][0];
				dist = routingTable[TOS_NODE_ID - 1][i][1];
				printf("Dest: %d  Next Hop: %d  Distance: %d\n",i + 1,nextHop,dist);
			//}
		}
	}
	
	command void LSRouting.printDVTable(){
		printf("DV Table of Node: %d\n",TOS_NODE_ID);
		for(i = 0; i < maxNodes; i++){
			for(j = 0; j < maxNodes; j++)
				printf("%d ",DVTable[TOS_NODE_ID - 1][i][j]);
			printf("\n");
		}
	}

	event void LSTimer.fired(){
		calculatePaths(TOS_NODE_ID);
	}

	uint16_t minNode(uint16_t curNodeID){
		min = maxNodes + 1;
		for(k = 0; k < maxNodes; k++){
			if(!considered[k] && routingTable[curNodeID - 1][k][1] <= min){
				min = routingTable[curNodeID - 1][k][1];
				minIndex = k;
			}
		}
		return minIndex;
	}
}