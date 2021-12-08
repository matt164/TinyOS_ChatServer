#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration floodingC{
	provides interface flooding;
}

implementation{
	components floodingP;
	flooding = floodingP.flooding;

	components new SimpleSendC(AM_PACK);
	floodingP.Sender -> SimpleSendC;
	
	components neighborDiscC;
	floodingP.neighborDisc -> neighborDiscC;
	
	components LSRoutingC;
	floodingP.LSRouting -> LSRoutingC;

	components TransportC;
	floodingP.Transport -> TransportC;
}
