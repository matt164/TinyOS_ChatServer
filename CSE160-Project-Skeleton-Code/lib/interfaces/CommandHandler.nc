interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint16_t port);
   event void setTestClient(uint16_t port, uint16_t dest, uint16_t dstPort, uint16_t transfer);
   event void setAppServer(uint16_t port);
   event void setAppClient(uint16_t port);
   event void sendChatCmd(uint8_t* chatCmd);
   /*event void hello(uint8_t* username);
   event void tellAll(uint8_t* msg);
   event void tell(uint8_t* recipient, uint8_t* msg);
   event void listUsers();*/
}
