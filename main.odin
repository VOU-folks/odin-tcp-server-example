package main

import "core:fmt"
import "core:net"
import "core:io"
import "core:thread"
import "core:time"
import "core:strings"

Client :: struct {
  socket: net.TCP_Socket,
  endpoint: net.Endpoint,
  endpoint_as_string: string,
}

new_client :: proc(socket: net.TCP_Socket, endpoint: net.Endpoint) -> ^Client {
  c := new(Client);
  c.socket = socket;
  c.endpoint = endpoint;
  c.endpoint_as_string = net.endpoint_to_string(endpoint);
  return c;
}

main :: proc() {
  endpoint, _ := net.parse_endpoint("127.0.0.1:8080");
  socket, err := net.listen_tcp(endpoint);
  defer net.close(socket);

  if err != nil {
    fmt.println("Error listening on socket: ", err);
    return;
  }

  fmt.println("Listening at ", net.endpoint_to_string(endpoint));

  for {
    connection, endpoint,  err := net.accept_tcp(socket);
    if err != nil {
      fmt.println("Error accepting connection: ", err);
      return;
    }

    client := new_client(connection, endpoint);
    fmt.println("Accepted connection from ", client.endpoint_as_string);

    t := thread.create(proc(t: ^thread.Thread) {
      client := cast (^Client) t.data;
      handle_client(client);
    });
    if t == nil {
      fmt.eprintln("Error creating thread");
      net.close(client.socket);
      continue;
    }


    t.user_index = len(threads);
    t.data = client;
    append(&threads, t);
    thread.start(t);
  }
}

threads : [dynamic]^thread.Thread;

@(init)
create_thread_pool :: proc() {
  threads := make([dynamic]^thread.Thread, 0);
  thread_cleaner();
}

destroy_thread_pool :: proc() {
  delete(threads);
}

thread_cleaner :: proc() {
  t := thread.create(proc(t : ^thread.Thread) {
    for {
      time.sleep(1 * time.Second);

      if len(threads) == 0 {
        continue;
      }

      for i := 0; i < len(threads); {
        if t := threads[i]; thread.is_done(t) {
          fmt.printf("Thread %d is done\n", t.user_index);
          t.data = nil;
          thread.destroy(t);

          ordered_remove(&threads, i);
        }
        else {
          i += 1;
        }
      }
    }
  });
  thread.start(t);
}


handle_client :: proc(client: ^Client) {
  buffer_size :: 10240;
  read_buffer : [buffer_size]byte = [buffer_size]byte{};
  bytes_read : int = 0;

  err : net.Network_Error = nil;

  for {
    bytes_read, err = net.recv_tcp(client.socket, read_buffer[:]);

    if err != nil {
      fmt.println("Error reading from socket: ", err);
      break;
    }

    if bytes_read == 0 {
      break;
    }

    net.send_tcp(client.socket, []u8{'o', 'k', '\n'});
    fmt.println("Received message from ", client.endpoint_as_string, ":", string(read_buffer[:]));
  }

  fmt.println("Closing connection with ", client.endpoint_as_string);
  net.close(client.socket);
}
