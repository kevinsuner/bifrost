package bifrost

import "core:strings"
import "core:testing"
import "core:log"

HttpResponse :: struct {
    status:     string,
    headers:    [dynamic]HttpHeader,
    body:       [dynamic]u8,
}

/*
Parses `buf` into an `^HttpResponse` struct

Inputs:
- buf: The input bytes

Returns:
- res: A pointer to an initialized `^HttpResponse` struct
- err: An enumerated value from `Parse_Error`
*/
@(private)
_parse_http_response :: proc(buf: []u8) -> (res: ^HttpResponse, err: Parse_Error) {
    str := string(buf)
    res = new(HttpResponse)
    found_blank_line: bool

    for line in strings.split_lines_iterator(&str) {
        if line == "" {
            // used as delimiter between headers and body
            found_blank_line = true
            continue
        }

        if res.status == "" {
            if !strings.contains(line, "HTTP") {
                // status line must contain HTTP
                return nil, .Status_Line_Not_Found
            }

            arr := strings.split(line, " ")
            defer delete(arr)
            
            if len(arr) < 3 {
                // status line must follow this format
                // [HTTP-version] [status-code] [reason-phrase]
                return nil, .Invalid_Status_Line
            }
            res.status = arr[1]
        } else {
            if found_blank_line {
                append(&res.body, ..transmute([]u8)line)
                continue
            }

            arr := strings.split_n(line, ":", 2)
            defer delete(arr)

            if len(arr) < 2 {
                // headers must follow this format
                // [key] : [val]
                return nil, .Invalid_Header
            }
            append(&res.headers, HttpHeader{arr[0], strings.trim(arr[1], " ")})
        }
    }
    return res, .None
}

@(test)
test_parse_http_response :: proc(t: ^testing.T) {
    response := "HTTP/1.1 200 OK\r\nHost: http://foo.com/\r\nConnection: keep-alive\r\n\r\n" + `{"foo": "bar"}`
    res, err := _parse_http_response(transmute([]u8)response)
    defer free(res)
    defer delete(res.headers)
    defer delete(res.body)
    log.infof("res: %v\n", res)
    log.infof("err: %v\n", err)
}
