#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration neighborDiscC{
	provides interface neighborDisc;
}

implementation{
	components neighborDiscP;
	neighborDisc = neighborDiscP.neighborDisc;

	components new SimpleSendC(AM_PACK);
	neighborDiscP.Sender -> SimpleSendC;
	
	components new TimerMilliC() as discTimer;
	neighborDiscP.discTimer -> discTimer;
	
	components floodingC;
	neighborDiscP.flooding -> floodingC;
	
	components LSRoutingC;
	neighborDiscP.LSRouting -> LSRoutingC;
}
