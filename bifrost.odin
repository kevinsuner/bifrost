package main

import "core:net"
import "core:os"
import "core:fmt"
import "core:strings"

// TODO:
// - Parse HTTP url into an HttpUrl structure 
//      - <protocol>://<hostname><path>?<params>
//      - HttpUrl { Proto, Host, Path, Params }
//      - https://github.com/golang/go/blob/master/src/net/url/url.go
// - Refactor build_http_request to take HttpUrl and Headers (map) as parameters
// - Parse HTTP response headers and body into an HttpResponse structure
// - Create a procedure to perform a dynamically allocated HTTP GET request

build_http_request :: proc(parsed_endpoint: net.Endpoint) -> []u8 {
  builder := strings.builder_make()
  strings.write_string(&builder, "GET / HTTP/1.1\r\n")
  strings.write_string(&builder, 
    fmt.aprintf(
      "Host: %s\r\n",
      net.endpoint_to_string(parsed_endpoint),
    ),
  )
  strings.write_string(&builder, "Connection: close\r\n")
  strings.write_string(&builder, "\r\n")
  return builder.buf[:]
}

connect_to_server :: proc(parsed_endpoint: net.Endpoint) -> (net.TCP_Socket, bool) {
  sock, err := net.dial_tcp_from_endpoint(
    parsed_endpoint,
    net.default_tcp_options,
  ) 
  if err != nil {
    return 0, false
  }
  return sock, true
}

send_http_request :: proc(sock: net.TCP_Socket, request: []u8) -> bool {
  if _, err := net.send_tcp(sock, request); err != nil {
    return false
  }
  return true
}

receive_http_response :: proc(sock: net.TCP_Socket, response: []u8) -> bool {
  received, err := net.recv_tcp(sock, response)
  if err != nil {
    return false
  }
  return true
}

main :: proc() {
  parsed_endpoint, ok_parse := net.parse_endpoint("0.0.0.0:8000")
  if !ok_parse {
    fmt.println("Failed to parse endpoint")
    return
  }

  sock, ok_sock := connect_to_server(parsed_endpoint)
  if !ok_sock {
    fmt.println("Failed to connect to server")
    return
  }

  request := build_http_request(parsed_endpoint) 
  response := make([]u8, 1024)

  recv_headers: bool
  recv_body: bool

  for {
    if recv_headers && recv_body {
      break
    }

    if ok_send := send_http_request(sock, request); !ok_send {
      fmt.println("Failed to send request")
      break
    }

    if ok_receive := receive_http_response(sock, response); !ok_receive {
      fmt.println("Failed to receive response")
      break
    }

    if strings.contains(string(response), "HTTP/1.0") {
      recv_headers = true
    }

    if strings.contains(string(response), "<!DOCTYPE HTML>") {
      recv_body = true
    }

    fmt.printf("Response:\n%s\n", response)
  }
}

