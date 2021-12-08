/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/chatClient.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
    
    components floodingC;
    Node.flooding -> floodingC;
    
    components neighborDiscC;
    Node.neighborDisc -> neighborDiscC;
    
    components LSRoutingC;
    Node.LSRouting -> LSRoutingC;

    components TransportC;
    Node.Transport -> TransportC;

    components new TimerMilliC() as ReadTimerC;
    Node.ReadTimer -> ReadTimerC;

    components new TimerMilliC() as WriteTimerC;
    Node.WriteTimer -> WriteTimerC;

    components new ListC(chatClient, MAX_NUM_OF_SOCKETS) as chatClientsC;
    Node.chatClients -> chatClientsC;
}
