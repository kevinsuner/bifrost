package bifrost

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
_percent_encode_str :: proc(str: string, allocator := context.allocator) -> (res: string) {
    sb := strings.builder_make(allocator)
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
    return strings.to_string(sb)
}

/*
Parses `str` into an `^Url` struct

Inputs:
- url: A pointer to an initialized `^Url` struct
- str: The input string
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An enumerated value from `URL_Error`

Example:

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        url := new(bifrost.Url)
        defer free(url)

        err := bifrost.parse_url(url, "https://foo.com/")
        if err != .None { fmt.printf("error: %v\n", err); return }
        fmt.printf("%v\n", url)
    }

Output:

    &Url{"https", "foo.com", "/", "", "", "https://foo.com/", 443}

*/
parse_url :: proc(url: ^Url, str: string, allocator := context.allocator) -> (err: URL_Error) {
    _has_control_character(str) or_return

    rest: string
    url.scheme, rest = _extract_scheme(str) or_return
    if url.scheme != "http" && url.scheme != "https" {
        return .Invalid_Scheme
    }
    url.port = 80 if url.scheme == "http" else 443

    url.host, rest = _extract_host(rest) or_return
    url.raw = str
    rest = _percent_encode_str(rest, allocator)

    url.fragment, _ = strings.substring(rest, strings.index(rest, "#"), len(rest))
    url.query, _ = strings.substring(rest, strings.index(rest, "?"), len(rest) - len(url.fragment))
    url.path, _ = strings.substring(rest, 0, len(rest) - len(url.query) - len(url.fragment))
    return
}

// Builds and HTTP request string
@(private)
_build_request :: proc(
    method: Request_Method,
    url: ^Url,
    headers: map[string]string,
    body: []u8,
    allocator := context.allocator,
) -> (res: []u8) {
    sb := strings.builder_make(0, (len(url.raw) + cap(headers) + len(body)) * 2, allocator)
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s %s%s%s HTTP/1.1\r\n", _request_method_to_str[method], url.path, url.query, url.fragment)
    fmt.sbprintf(&sb, "Host: %s\r\nConnection: close\r\n", url.host)
    for key, val in headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", key, val)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, body)
    return sb.buf[:]
}

// Parses `data` into an `^Response` struct
@(private)
_parse_response :: proc(res: ^Response, data: string, allocator := context.allocator) -> (err: Response_Error) {
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
            defer delete(arr)
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
            defer delete(arr)
            if len(arr) < 2 || len(arr[0]) == 0 {
                return .Invalid_Header
            }
            res.headers[arr[0]] = strings.trim(arr[1], " ")
        }
    }
    return
}

/*
Makes an HTTP request using OpenSSL and parses the response into a `^Response` struct

Inputs:
- res: A pointer to an initialized `^Response` struct
- method: An enumerated value from `Request_Method`
- url: A pointer to an initialized `^Url` struct
- headers: A string map representing the request headers
- body: A slice of bytes representing the request body
- length: The expected length of the response (default is 1kb)
- allocator: A custom memory allocator (default is context.allocator)

Returns:
- err: An enumerated value from `SSL_Error` or `Response_Error`

Example:

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        url := new(bifrost.Url)
        defer free(url)

        parse_err := bifrost.parse_url(url, "https://foo.com/")
        if parse_err != .None { fmt.printf("error: %v\n", parse_err); return }

        res := new(bifrost.Response)
        defer free(res)

        request_err := bifrost.make_request(res, .Get, url, nil, nil)
        if request_err != .None { fmt.printf("error: %v\n", request_err); return }
        fmt.printf("%v\n", res)
    }

Output:

    &Response{map[Host="foo.com", Connection="close"], "HTTP/1.1", "OK", {}, 200}

*/
make_request :: proc(
    res: ^Response,
    method: Request_Method,
    url: ^Url,
    headers: map[string]string,
    body: []u8,
    length := DEFAULT_RESPONSE_LENGTH,
    allocator := context.allocator,
) -> (err: Request_Error) {
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

    ep4 := net.resolve_ip4(fmt.tprintf("%s:%d", url.host, url.port)) or_return
    sockfd := net.dial_tcp_from_endpoint(ep4) or_return
    defer net.close(sockfd)

    if openssl.SSL_set_fd(ssl, i32(sockfd)) <= 0 {
        return .Unknown
    }

    openssl.SSL_set_tlsext_host_name(ssl, strings.clone_to_cstring(url.host))
    if openssl.SSL_connect(ssl) <= 0 {
        return .Unknown
    }

    request := _build_request(method, url, headers, body, allocator)
    if openssl.SSL_write(ssl, raw_data(request), i32(len(request))) <= 0 {
        return .Unknown
    }

    data := make([^]u8, length)
    defer free(data)
    for openssl.SSL_read(ssl, data, i32(length - 1)) > 0 {
        err = _parse_response(res, strings.string_from_ptr(data, length), allocator)
        if err != nil { return }
    }
    return
}

