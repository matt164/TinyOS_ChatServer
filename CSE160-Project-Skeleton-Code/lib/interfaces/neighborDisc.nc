#include "../../includes/packet.h"

interface neighborDisc{
	command void discInit();
	command void receiveRequest(pack *msg, uint16_t curNodeID);
	command void receiveReply(pack *msg, uint16_t curNodeID);
	command uint16_t getRequests(uint16_t nodeID, uint16_t neighborID);
	command uint16_t getReplies(uint16_t nodeID, uint16_t neighborID);
}
