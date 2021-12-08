#ifndef CHATCLIENT_H
#define CHATCLIENT_H

#include "socket.h"

typedef struct chatClient{
	char username[16];
	socket_t socket;
}chatClient;

#endif