#include "../../includes/packet.h"

interface flooding{
	command void flood(pack *msg, uint16_t curNodeID);
	command uint16_t nodeSeq(uint16_t nodeID);
}
