package bifrost

import "core:mem"
import "core:net"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "openssl"

DEFAULT_RESPONSE_LENGTH :: 1024

Request_Error :: union #shared_nil {
    URL_Error,
    Response_Error,
    SSL_Error,
    mem.Allocator_Error,
    net.Network_Error,
}

URL_Error :: enum {
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

SSL_Error :: enum {
    None,
    // Found an OpenSSL error
    Unknown,
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
_has_control_character :: proc(str: string) -> (err: URL_Error) {
    for _, i in str {
        if str[i] < ' ' || str[i] == 0x7f {
            return .Found_Control_Character
        }
    }
    return .None
}

// Extracts the HTTP scheme part from `str`
@(private)
_extract_scheme :: proc(str: string) -> (res, rest: string, err: URL_Error) {
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
_extract_host :: proc(str: string) -> (res, rest: string, err: URL_Error) {
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
_percent_encode_str :: proc(str: string, allocator := context.allocator) -> (res: string, err: mem.Allocator_Error) {
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
    return strings.to_string(sb), .None
}

/*
Initializes a `Url` struct

*Allocates using provided allocator*

Inputs:
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- url: A pointer to the `Url`
- err: An optional `mem.Allocator_Error` if one occured, `nil` otherwise
*/
url_init :: proc(allocator := context.allocator) -> (url: ^Url, err: mem.Allocator_Error) #optional_allocator_error {
    url = new(Url, allocator) or_return
    return
}

/*
Frees an initialized `Url` struct

Inputs:
- url: A pointer to the `Url`
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
- url: A pointer to the `Url`
- raw_url: The input string
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An error from `URL_Error` or `mem.Allocator_Error`, `nil` otherwise
*/
url_parse :: proc(url: ^Url, raw_url: string, allocator := context.allocator) -> (err: Request_Error) {
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
- req: A pointer to the `Request` struct
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
    str := string(data)
    found_delimiter: bool

    for line in strings.split_lines_iterator(&str) {
        if line == "" {
            found_delimiter = true
            continue
        }

        if res.status == 0 {
            if !strings.contains(line, "HTTP") {
                return .Status_Line_Not_Found
            }

            arr := strings.split(line, " ", allocator)
            defer delete(arr, allocator)
            if len(arr) < 3 {
                return .Invalid_Status_Line
            }
            res.version, res.reason = arr[0], arr[2]

            res.status = u16(strconv.parse_uint(arr[1]) or_else 0)
            if res.status == 0 {
                return .Invalid_Status
            }
        } else {
            if found_delimiter {
                res.body = transmute([]u8)data[strings.last_index(data, "\n")+1:]
                break
            }

            arr := strings.split_n(line, ":", 2, allocator)
            defer delete(arr, allocator)
            if len(arr) < 2 || len(arr[0]) == 0 {
                return .Invalid_Header
            }
            res.headers[arr[0]] = strings.trim(arr[1], " ")
        }
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
- err: An error from `SSL_Error`, `Response_Error`, `net.Network_Error` or `mem.Allocator_Error`, `nil` otherwise
*/
request_do :: proc(req: ^Request, length := DEFAULT_RESPONSE_LENGTH, allocator := context.allocator) -> (err: Request_Error) {
    ctx := openssl.SSL_CTX_new(openssl.TLS_client_method())
    defer openssl.SSL_CTX_free(ctx)
    if ctx == nil {
        return .Unknown
    }

    ssl := openssl.SSL_new(ctx)
    defer openssl.SSL_free(ssl)
    if ssl == nil {
        return .Unknown
    }

    ep4 := net.resolve_ip4(fmt.tprintf("%s:%d", req.url.host, req.url.port)) or_return
    sockfd := net.dial_tcp_from_endpoint(ep4) or_return
    defer net.close(sockfd)

    if openssl.SSL_set_fd(ssl, i32(sockfd)) <= 0 {
        return .Unknown
    }

    openssl.SSL_set_tlsext_host_name(ssl, strings.clone_to_cstring(req.url.host))
    if openssl.SSL_connect(ssl) <= 0 {
        return .Unknown
    }

    request := _request_to_str(req, allocator) or_return
    if openssl.SSL_write(ssl, raw_data(request), i32(len(request))) <= 0 {
        return .Unknown
    }

    data := make([^]u8, length)
    defer free(data)
    for openssl.SSL_read(ssl, data, i32(length - 1)) > 0 {
        _response_parse(req.res, strings.string_from_ptr(data, length), allocator) or_return
    }
    return
}

