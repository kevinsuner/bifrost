package main

import "core:net"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:bytes"
import "core:strconv"
// import "core:mem"

/*

backing_buffer := make([]byte, 2*mem.Kilobyte)
defer delete(backing_buffer)

arena: mem.Arena
mem.arena_init(&arena, backing_buffer)

buffer, err_alloc := mem.arena_alloc_bytes(&arena, 1*mem.Kilobyte)     
if err_alloc != nil {
  fmt.println("Failed to alloc bytes")
  break
}

*/

extract_status_code :: proc(response: string) -> int {
  index := strings.index(response, "HTTP/1.0")
  if index != -1 {
    status_line, _ := strings.substring_from(response, index)
    status_code := strings.split(status_line, " ")[1]
    return strconv.atoi(status_code)
  }
  
  return 0
}

main :: proc() {
  socket, err_dial := net.dial_tcp_from_host(
    net.Host{"0.0.0.0", 8000},
    net.default_tcp_options,
  )
  if err_dial != nil {
    fmt.printf("Failed to dial tcp: %v\n", err_dial)
    return
  }

  builder := strings.builder_make() 
  strings.write_string(&builder, "GET / HTTP/1.1\r\n")
  strings.write_string(&builder, "Host: 0.0.0.0:8000\r\n")
  strings.write_string(&builder, "Connection: close\r\n")
  strings.write_string(&builder, "\r\n")

  buffer: [1024]u8
  for {
    bytes_sent, err_sent := net.send_tcp(socket, builder.buf[:])
    if err_sent != nil {
      if err_sent == net.TCP_Send_Error.Connection_Closed {
        fmt.println("Connection closed")
        break
      }

      fmt.printf("Failed to send data: %v\n", err_sent)
      break
    }

    bytes_recv, err_recv := net.recv_tcp(socket, buffer[:])
    if err_recv != nil {
      fmt.printf("Failed to recv data: %v\n", err_recv)
      break
    }

    bytes: [1024]u8
    sbuilder := strings.builder_from_bytes(bytes[:])
    strings.write_bytes(&sbuilder, buffer[:bytes_recv])

    code := extract_status_code(strings.to_string(sbuilder))
    fmt.printf("Status code: %d\n", code)
    received := buffer[:bytes_recv]
    fmt.printf("Client received [ %d bytes ]: %s", len(received), received)
  }

  net.close(socket)
}

