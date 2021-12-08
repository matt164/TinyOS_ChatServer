#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration LSRoutingC{
	provides interface LSRouting;
}

implementation{
	components LSRoutingP;
	LSRouting = LSRoutingP.LSRouting;

	components new SimpleSendC(AM_PACK);
	LSRoutingP.Sender -> SimpleSendC;

	components new TimerMilliC() as LSTimer;
	LSRoutingP.LSTimer -> LSTimer;
}