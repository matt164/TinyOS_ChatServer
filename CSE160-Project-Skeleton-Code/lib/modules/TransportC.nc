#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include <stdlib.h>

configuration TransportC{
	provides interface Transport;
}

implementation{
	components TransportP;
	Transport = TransportP;

	components new ListC(pack, MAX_OUTSTANDING) as waitingForAckC;
	TransportP.waitingForAck -> waitingForAckC;

	components new ListC(uint32_t, MAX_OUTSTANDING) as resendAtC;
	TransportP.resendAt -> resendAtC;

	components new ListC(socket_t, MAX_OUTSTANDING) as socketListC;
	TransportP.socketList -> socketListC;

	components new TimerMilliC() as resendTimerC;
	TransportP.resendTimer -> resendTimerC;

}