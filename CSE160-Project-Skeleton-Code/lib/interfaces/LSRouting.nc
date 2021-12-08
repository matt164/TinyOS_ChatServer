#include "../../includes/packet.h"

interface LSRouting{
	command void LSInit();
	command void updateNeighbors(pack *msg, uint16_t curNodeID);
	command uint16_t getNextHop(uint16_t curNodeID, uint16_t destNodeID);
	command void printRouteTable();
	command void printDVTable();
}
