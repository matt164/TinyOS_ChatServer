from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    #s.addChannel(s.COMMAND_CHANNEL);
    #s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.

    s.runTime(300);
    s.appServer(1,41);
    s.runTime(60);

    s.appClient(4, 150);
    s.runTime(60);

    s.appClient(5, 160);
    s.runTime(60);

    s.sendChatCommand(4, "hello Matt\r\n");
    s.runTime(60);

    s.sendChatCommand(5, "hello Jim\r\n");
    s.runTime(200);

    s.sendChatCommand(4, "listusr \r\n");
    s.runTime(60);

    s.sendChatCommand(4, "msg Hello everyone!\r\n");
    s.runTime(60);

    s.sendChatCommand(4, "whisper Jim Hi Jim!\r\n");
    s.runTime(1000);

if __name__ == '__main__':
    main()
