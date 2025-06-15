package bifrost

import "core:mem"
import "core:net"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "openssl"

DEFAULT_RESPONSE_LENGTH :: 1024

Client_Error :: union #shared_nil {
    Url_Error,
    Response_Error,
    Ssl_Error,
    mem.Allocator_Error,
    net.Network_Error,
}

Url_Error :: enum {
    None,
    // Found an ASCII control character
    Found_Control_Character,
    // Unable to extract scheme part of http url
    Scheme_Not_Found,
    // Scheme is neither `http` nor `https`
    Invalid_Scheme,
    // Unable to extract host part of http url
    Host_Not_Found,
}

Response_Error :: enum {
    None,
    // Unable to find response's status line
    Status_Line_Not_Found,
    // Status line is wrongly formatted
    Invalid_Status_Line,
    // Status code is not in the 2XX-5XX range
    Invalid_Status,
    // Header is wrongly formatted
    Invalid_Header,
}

Ssl_Error :: enum {
    None,
    // Failed to create a new SSL_CTX object
    SSL_CTX_Failed,
    // Failed to create a new SSL structure
    SSL_New_Failed,
    // Failed to set the file descriptor
    SSL_Set_FD_Failed,
    // Failed to perform TLS/SSL handshake
    SSL_Connect_Failed,
    // Failed to perform the write operation
    SSL_Write_Failed,
}

Request_Method :: enum {
    Get,
    Head,
    Options,
    Put,
    Delete,
    Post,
    Patch,
}

@(private)
_request_method_to_str := [Request_Method]string{
    .Post       = "POST",
    .Get        = "GET",
    .Put        = "PUT",
    .Patch      = "PATCH",
    .Delete     = "DELETE",
    .Head       = "HEAD",
    .Options    = "OPTIONS",
}

Url :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
    raw:        string,
    port:       u16,
}

Request :: struct {
    headers:    map[string]string,
    body:       []u8,
    method:     Request_Method,
    url:        ^Url,
    res:        ^Response,
}

Response :: struct {
    headers:    map[string]string,
    version:    string,
    reason:     string,
    body:       []u8,
    status:     u16,
}

// Reports whether `str` contains any ASCII control character
@(private)
_has_control_character :: proc(str: string) -> (err: Url_Error) {
    for _, i in str {
        if str[i] < ' ' || str[i] == 0x7f {
            return .Found_Control_Character
        }
    }
    return .None
}

// Extracts the HTTP scheme part from `str`
@(private)
_extract_scheme :: proc(str: string) -> (res, rest: string, err: Url_Error) {
    for c, i in str {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z':
            continue

        case '0' <= c && c <= '9' || c == '+' || c == '-' || c == '.':
            if i == 0 {
                // [0-9+-.] found at the beginning
                return "", str, .Scheme_Not_Found
            }

        case c == ':':
            if i == 0 {
                // colon found at the beginning
                return "", str, .Scheme_Not_Found
            }
            return str[:i], str[i+1:], .None

        case:
            // invalid character found
            return "", str, .Scheme_Not_Found
        }
    }
    return "", str, .Scheme_Not_Found
}

// Extracts the HTTP host part from `str`
@(private)
_extract_host :: proc(str: string) -> (res, rest: string, err: Url_Error) {
    s := strings.trim_prefix(str, "//")
    hyphen_pos, period_pos: int

    for c, i in s {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9':
            continue

        case c == '-':
            if i == 0 || i == len(s)-1 {
                // hyphen found at the beginning or end
                return "", str, .Host_Not_Found
            }
            hyphen_pos = i

        case c == '.':
            if i == 0 || i == len(s)-1 {
                // period found at the beginning or end
                return "", str, .Host_Not_Found
            }
            period_pos = i

        case c == '/' || c == '?' || c == '#':
            if i == 0 || hyphen_pos == i-1 || period_pos == i-1 {
                // [/?#] found at the beginning or after hyphen/period
                return "", str, .Host_Not_Found
            }

            if period_pos != 0 {
                return s[:i], s[i:], .None
            }

        case:
            // invalid character found
            return "", str, .Host_Not_Found
        }
    }
    return "", str, .Host_Not_Found
}

// Escapes specific characters from `str` using percent-encoding
@(private)
_percent_encode_str :: proc(str: string, allocator := context.allocator) -> (res: string, err: mem.Allocator_Error) #optional_allocator_error {
    sb := strings.builder_make(allocator) or_return
    defer strings.builder_destroy(&sb)

    for c, _ in str {
        switch {
        case c == ' ':
            strings.write_string(&sb, "%20")

        case c == ';':
            strings.write_string(&sb, "%3B")

        case c == ':':
            strings.write_string(&sb, "%3A")

        case c == '[':
            strings.write_string(&sb, "%5B")

        case c == ']':
            strings.write_string(&sb, "%5D")

        case c == '{':
            strings.write_string(&sb, "%7B")

        case c == '}':
            strings.write_string(&sb, "%7D")

        case c == '<':
            strings.write_string(&sb, "%3C")

        case c == '>':
            strings.write_string(&sb, "%3E")

        case c == '\\':
            strings.write_string(&sb, "%5C")

        case c == '^':
            strings.write_string(&sb, "%5E")

        case c == '`':
            strings.write_string(&sb, "%60")

        case c == '"':
            strings.write_string(&sb, "%22")

        case:
            strings.write_rune(&sb, c)
        }
    }

    res = strings.to_string(sb)
    return
}

/*
Initializes a `Url` struct

*Allocates using provided allocator*

Inputs:
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- url: A pointer to an `Url` struct
- err: An optional `mem.Allocator_Error` if one occured, `nil` otherwise
*/
url_init :: proc(allocator := context.allocator) -> (url: ^Url, err: mem.Allocator_Error) #optional_allocator_error {
    url = new(Url, allocator) or_return
    return
}

/*
Frees an initialized `Url` struct

Inputs:
- url: A pointer to an `Url` struct
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An optional `mem.Allocator_Error` if one occured, `nil` otherwise
*/
url_free :: proc(url: ^Url, allocator := context.allocator) -> (err: mem.Allocator_Error) {
    return free(url, allocator)
}

/*
Parses `raw_url` into an `Url` struct

Inputs:
- url: A pointer to an `Url` struct
- raw_url: The input string
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An error from `Url_Error` or `mem.Allocator_Error`, `nil` otherwise
*/
url_parse :: proc(url: ^Url, raw_url: string, allocator := context.allocator) -> (err: Client_Error) {
    _has_control_character(raw_url) or_return

    rest: string
    url.scheme, rest = _extract_scheme(raw_url) or_return
    if url.scheme != "http" && url.scheme != "https" {
        return .Invalid_Scheme
    }
    url.port = 80 if url.scheme == "http" else 443

    url.host, rest = _extract_host(rest) or_return
    rest = _percent_encode_str(rest, allocator) or_return

    url.fragment, _ = strings.substring(rest, strings.index(rest, "#"), len(rest))
    url.query, _ = strings.substring(rest, strings.index(rest, "?"), len(rest) - len(url.fragment))
    url.path, _ = strings.substring(rest, 0, len(rest) - len(url.query) - len(url.fragment))

    url.raw = raw_url
    return
}

/*
Initializes a `Request` struct

*Allocates using provided allocator*

Inputs:
- method: An enumerated value from `Request_Method`
- url: A pointer to an `Url` struct
- body: A slice of bytes representing the request body
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- req: A pointer to a `Request` struct
- err: An optional `mem.Allocator_Error` if one occured, `nil` otherwise
*/
request_init :: proc(method: Request_Method, url: ^Url, body: []u8, allocator := context.allocator) -> (req: ^Request, err: mem.Allocator_Error) #optional_allocator_error {
    req = new(Request, allocator) or_return
    req.headers = make(map[string]string, 0, allocator) or_return
    req.body = body
    req.method = method
    req.url = url
    req.res = new(Response, allocator) or_return
    return
}

/*
Frees an initialized `Request` struct

Inputs:
- req: A pointer to a `Request` struct
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An optional `mem.Allocator_Error` if one occured, `nil` otherwise
*/
request_free :: proc(req: ^Request, allocator := context.allocator) -> (err: mem.Allocator_Error) {
    delete(req.headers) or_return
    delete(req.res.headers) or_return
    free(req.res, allocator) or_return
    return free(req, allocator)
}

// Builds an HTTP request string using an initialized `Request` struct
@(private)
_request_to_str :: proc(req: ^Request, allocator := context.allocator) -> (res: string, err: mem.Allocator_Error) #optional_allocator_error {
    sb := strings.builder_make(0, (len(req.url.raw) + cap(req.headers) + len(req.body)) * 2, allocator) or_return
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s %s%s%s HTTP/1.1\r\n", _request_method_to_str[req.method], req.url.path, req.url.query, req.url.fragment)
    fmt.sbprintf(&sb, "Host: %s\r\nConnection: close\r\n", req.url.host)
    for key, val in req.headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", key, val)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, req.body)

    res = strings.to_string(sb)
    return
}

// Parses `data` into an initialized `Response` struct
@(private)
_response_parse :: proc(res: ^Response, data: string, allocator := context.allocator) -> (err: Response_Error) {
    status_line_end := strings.index(data, "\r\n")
    status_line := data[:status_line_end]
    if !strings.contains(status_line, "HTTP") {
        return .Status_Line_Not_Found
    }

    status_line_parts := strings.split(status_line, " ", allocator)
    defer delete(status_line_parts, allocator)
    if len(status_line_parts) < 3 {
        return .Invalid_Status_Line
    }
    res.version = status_line_parts[0]
    res.reason = status_line_parts[2]
    res.status = u16(strconv.parse_uint(status_line_parts[1]) or_else 0)
    if res.status == 0 {
        return .Invalid_Status
    }

    headers_end := strings.index(data, "\r\n\r\n")
    headers := data[status_line_end + 2:headers_end]
    lines := strings.split_lines(headers, allocator)
    defer delete(lines, allocator)
    for line in lines {
        header_parts := strings.split_n(line, ":", 2, allocator)
        defer delete(header_parts, allocator)
        if len(header_parts) < 2 || len(header_parts[0]) == 0 {
            return .Invalid_Header
        }
        res.headers[header_parts[0]] = strings.trim(header_parts[1], " ")
    }

    content_length := strconv.parse_uint(res.headers["Content-Length"]) or_else 0
    if content_length != 0 {
        body_start := headers_end + 4
        body_end := body_start + int(content_length)
        res.body = transmute([]u8)data[body_start:body_end]
    }
    return
}

/*
Performs an HTTP request using OpenSSL and parses the response into an initialized `Response` struct

Inputs:
- req: A pointer to a `Request` struct
- length: The expected length of the response (default is 1kb)
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An error from `Response_Error`, `Ssl_Error`, `mem.Allocator_Error` or `net.Network_Error`, `nil` otherwise
*/
request_do :: proc(req: ^Request, length := DEFAULT_RESPONSE_LENGTH, allocator := context.allocator) -> (err: Client_Error) {
    ctx := openssl.SSL_CTX_new(openssl.TLS_client_method())
    defer openssl.SSL_CTX_free(ctx)
    if ctx == nil {
        return .SSL_CTX_Failed
    }

    ssl := openssl.SSL_new(ctx)
    defer openssl.SSL_free(ssl)
    if ssl == nil {
        return .SSL_New_Failed
    }

    ep4 := net.resolve_ip4(fmt.tprintf("%s:%d", req.url.host, req.url.port)) or_return
    sockfd := net.dial_tcp_from_endpoint(ep4) or_return
    defer net.close(sockfd)

    if openssl.SSL_set_fd(ssl, i32(sockfd)) <= 0 {
        return .SSL_Set_FD_Failed
    }

    openssl.SSL_set_tlsext_host_name(ssl, strings.clone_to_cstring(req.url.host))
    if openssl.SSL_connect(ssl) <= 0 {
        return .SSL_Connect_Failed
    }

    request := _request_to_str(req, allocator) or_return
    if openssl.SSL_write(ssl, raw_data(request), i32(len(request))) <= 0 {
        return .SSL_Write_Failed
    }

    chunk := make([]u8, length, allocator)
    defer delete(chunk, allocator)
    data := make([dynamic]u8, 0, allocator)
    defer delete(data)

    for {
        bytes := openssl.SSL_read(ssl, &chunk[0], i32(length))
        if bytes <= 0 { break }
        append(&data, ..chunk[:bytes])
    }
    return _response_parse(req.res, string(data[:]), allocator)
}

