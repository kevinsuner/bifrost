package bifrost

import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:testing"

Parse_Error :: enum {
    None,
    // Found an ASCII control character
    Found_Control_Character,
    // Unable to extract scheme part of http url
    Scheme_Not_Found,
    // Scheme is neither `http` nor `https`
    Invalid_Scheme,
    // Unable to extract host part of http url
    Host_Not_Found,
    // Unable to find response's status line
    Status_Line_Not_Found,
    // Status line is wrongly formatted
    Invalid_Status_Line,
    // Status code is not in the 2XX-5XX range
    Invalid_Status,
    // Header is wrongly formatted
    Invalid_Header,
}

/*
Reports whether `str` contains any ASCII control character

Inputs:
- str: The input string

Returns:
- err: An enumerated value from `Parse_Error`
*/
@(private)
_has_control_character :: proc(str: string) -> (err: Parse_Error) {
    for _, i in str {
        if str[i] < ' ' || str[i] == 0x7f {
            return .Found_Control_Character
        }
    }
    return .None
}

/*
Extracts the http scheme part from `str`

Inputs:
- str: The input string

Returns:
- res: The http scheme
- rest: The rest of the string
- err: An enumerated value from `Parse_Error`
*/
@(private)
_extract_scheme :: proc(str: string) -> (res, rest: string, err: Parse_Error) {
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

/*
Extracts the http host part from `str`

Inputs:
- str: The input string

Returns:
- res: The http host
- rest: The rest of the string
- err: An enumerated value from `Parse_Error`
*/
@(private)
_extract_host :: proc(str: string) -> (res, rest: string, err: Parse_Error) {
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

/*
Escapes specific characters from `str` using percent-encoding

Inputs:
- str: The input string

Returns:
- res: The percent-encoded string
*/
@(private)
_percent_encode_str :: proc(str: string) -> (res: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    for c, i in str {
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

Url :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
    raw:        string,
    port:       u16,
}

/*
Parses `str` into an `Url` struct

Inputs:
- str: The input string

Returns:
- res: An initialized `Url` struct
- err: An enumerated value from `Parse_Error`

Example:

    import "core:fmt"
    import "libs/bifrost"

    main :: proc() {
        fmt.printf("%v\n", bifrost.parse_url("https://foo.com/"))
    }

Output:

    Url{"https", "foo.com", "/", "", "", "https://foo.com/", 443}

*/
parse_url :: proc(str: string) -> (res: Url, err: Parse_Error) {
    _has_control_character(str) or_return

    rest: string
    res.scheme, rest = _extract_scheme(str) or_return
    if res.scheme != "http" && res.scheme != "https" {
        return {}, .Invalid_Scheme
    }
    res.port = 80 if res.scheme == "http" else 443

    res.host, rest = _extract_host(rest) or_return
    res.raw = fmt.tprintf("%s://%s%s", res.scheme, res.host, rest)
    rest = _percent_encode_str(rest)

    res.fragment, _ = strings.substring(rest, strings.index(rest, "#"), len(rest))
    res.query, _ = strings.substring(rest, strings.index(rest, "?"), len(rest) - len(res.fragment))
    res.path, _ = strings.substring(rest, 0, len(rest) - len(res.query) - len(res.fragment))
    return
}

Method :: enum {
    Get,
    Head,
    Options,
    Put,
    Delete,
    Post,
    Patch,
}

@(private)
_method_to_str := [Method]string{
    .Post       = "POST",
    .Get        = "GET",
    .Put        = "PUT",
    .Patch      = "PATCH",
    .Delete     = "DELETE",
    .Head       = "HEAD",
    .Options    = "OPTIONS",
}

/*
Builds and HTTP request string

Inputs:
- method: An enumerated value from `Method`
- url: An initialized `Url` struct
- headers: A string map representing the request headers
- body: A slice of bytes representing the request body

Returns:
- res: A slice of bytes representing the request
*/
@(private)
_build_request :: proc(method: Method, url: Url, headers: map[string]string, body: []u8) -> (res: []u8) {
    sb := strings.builder_make(0, (len(url.raw) + cap(headers) + len(body)) * 2)
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s %s%s%s HTTP/1.1\r\n", _method_to_str[method], url.path, url.query, url.fragment)
    fmt.sbprintf(&sb, "Host: %s\r\n", url.host)
    for key, val in headers {
        fmt.sbprintf(&sb, "%s: %s\r\n", key, val)
    }

    strings.write_string(&sb, "\r\n")
    strings.write_bytes(&sb, body)
    return sb.buf[:]
}

Response :: struct {
    headers:    map[string]string,
    version:    string,
    reason:     string,
    body:       []u8,
    status:     u16,
}

/*
Parses `buf` into an `^Response` struct

Inputs:
- buf: The input bytes

Returns:
- res: A pointer to an initialized `^Response` struct
- err: An enumerated value from `Parse_Error`
*/
@(private)
_parse_response :: proc(buf: []u8) -> (res: ^Response, err: Parse_Error) {
    res = new(Response)
    str := string(buf)
    found_delimiter: bool

    for line in strings.split_lines_iterator(&str) {
        if line == "" {
            found_delimiter = true
            continue
        }

        if res.status == 0 {
            if !strings.contains(line, "HTTP") {
                return nil, .Status_Line_Not_Found
            }

            arr := strings.split(line, " ")
            defer delete(arr)
            if len(arr) < 3 {
                return nil, .Invalid_Status_Line
            }
            res.version, res.reason = arr[0], arr[2]

            res.status = u16(strconv.parse_uint(arr[1]) or_else 0)
            if res.status == 0 {
                return nil, .Invalid_Status
            }
        } else {
            if found_delimiter {
                res.body = buf[strings.last_index(string(buf), "\n")+1:]
                break
            }

            arr := strings.split_n(line, ":", 2)
            defer delete(arr)
            if len(arr) < 2 || len(arr[0]) == 0 {
                return nil, .Invalid_Header
            }
            res.headers[arr[0]] = strings.trim(arr[1], " ")
        }
    }
    return
}

@(test)
test_has_control_character :: proc(t: ^testing.T) {
    tests := []struct{str: string, err: Parse_Error}{
        {"https://foo.com/bar?foo=bar#foo", .None},
        {"https://foo.com/bar?foo=bar#foo\n", .Found_Control_Character},
        {"https://foo.com/bar?foo=bar#foo\r", .Found_Control_Character},
        {"https://foo.com/bar?foo=bar#foo\x7f", .Found_Control_Character},
    }
    for test, _ in tests {
        testing.expect_value(t, _has_control_character(test.str), test.err)
    }
}

@(test)
test_extract_scheme :: proc(t: ^testing.T) {
    tests := []struct{str, res, rest: string, err: Parse_Error}{
        {"http://foo.com/bar?foo=bar#foo", "http", "//foo.com/bar?foo=bar#foo", .None},
        {"https://foo.com/bar?foo=bar#foo", "https", "//foo.com/bar?foo=bar#foo", .None},
        {"0https://foo.com/bar?foo=bar#foo", "", "0https://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {"+https://foo.com/bar?foo=bar#foo", "", "+https://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {"-https://foo.com/bar?foo=bar#foo", "", "-https://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {".https://foo.com/bar?foo=bar#foo", "", ".https://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {"://foo.com/bar?foo=bar#foo", "", "://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {" https://foo.com/bar?foo=bar#foo", "", " https://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {"h ttps://foo.com/bar?foo=bar#foo", "", "h ttps://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
        {"h_ttps://foo.com/bar?foo=bar#foo", "", "h_ttps://foo.com/bar?foo=bar#foo", .Scheme_Not_Found},
    }
    for test, _ in tests {
        res, rest, err := _extract_scheme(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, rest, test.rest)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_extract_host :: proc(t: ^testing.T) {
    tests := []struct{str, res, rest: string, err: Parse_Error}{
        {"//foo.com/bar?foo=bar#foo", "foo.com", "/bar?foo=bar#foo", .None},
        {"//foo.bar.com/bar?foo=bar#foo", "foo.bar.com", "/bar?foo=bar#foo", .None},
        {"//.foo.com/bar?foo=bar#foo", "", "//.foo.com/bar?foo=bar#foo", .Host_Not_Found},
        {"//foo.com./bar?foo=bar#foo", "", "//foo.com./bar?foo=bar#foo", .Host_Not_Found},
        {"//-foo.com/bar?foo=bar#foo", "", "//-foo.com/bar?foo=bar#foo", .Host_Not_Found},
        {"//foo.com-/bar?foo=bar#foo", "", "//foo.com-/bar?foo=bar#foo", .Host_Not_Found},
        {"//foo/bar?foo=bar#foo", "", "//foo/bar?foo=bar#foo", .Host_Not_Found},
        {"//f oo.com/bar?foo=bar#foo", "", "//f oo.com/bar?foo=bar#foo", .Host_Not_Found},
        {"//f_oo.com/bar?foo=bar#foo", "", "//f_oo.com/bar?foo=bar#foo", .Host_Not_Found},
    }
    for test, _ in tests {
        res, rest, err := _extract_host(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, rest, test.rest)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_percent_encode_str :: proc(t: ^testing.T) {
    tests := []struct{str, res: string}{
        { "/bar?foo=bar #foo", "/bar?foo=bar%20#foo" },
        { "/bar?foo=bar;#foo", "/bar?foo=bar%3B#foo" },
        { "/bar?foo=bar:#foo", "/bar?foo=bar%3A#foo" },
        { "/bar?foo=bar[#foo", "/bar?foo=bar%5B#foo" },
        { "/bar?foo=bar]#foo", "/bar?foo=bar%5D#foo" },
        { "/bar?foo=bar{#foo", "/bar?foo=bar%7B#foo" },
        { "/bar?foo=bar}#foo", "/bar?foo=bar%7D#foo" },
        { "/bar?foo=bar<#foo", "/bar?foo=bar%3C#foo" },
        { "/bar?foo=bar>#foo", "/bar?foo=bar%3E#foo" },
        { "/bar?foo=bar\\#foo", "/bar?foo=bar%5C#foo" },
        { "/bar?foo=bar^#foo", "/bar?foo=bar%5E#foo" },
        { "/bar?foo=bar`#foo", "/bar?foo=bar%60#foo" },
        { `/bar?foo=bar"#foo`, "/bar?foo=bar%22#foo" },
    }
    for test, _ in tests {
        testing.expect_value(t, _percent_encode_str(test.str), test.res)
    }
}

@(test)
test_parse_url :: proc(t: ^testing.T) {
    tests := []struct{str: string, res: Url, err: Parse_Error}{
        {"http://foo.com/bar?foo=bar&bar=foo#foo", {"http", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "http://foo.com/bar?foo=bar&bar=foo#foo", 80}, .None},
        {"https://foo.com/bar?foo=bar&bar=foo#foo", {"https", "foo.com", "/bar", "?foo=bar&bar=foo", "#foo", "https://foo.com/bar?foo=bar&bar=foo#foo", 443}, .None},
        {"https://foo.bar.com/bar?foo=bar#foo", {"https", "foo.bar.com", "/bar", "?foo=bar", "#foo", "https://foo.bar.com/bar?foo=bar#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar#foo", {"https", "foo.com", "/bar", "?foo=bar", "#foo", "https://foo.com/bar?foo=bar#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar #foo", {"https", "foo.com", "/bar", "?foo=bar%20", "#foo", "https://foo.com/bar?foo=bar #foo", 443}, .None},
        {"https://foo.com/bar?foo=bar;#foo", {"https", "foo.com", "/bar", "?foo=bar%3B", "#foo", "https://foo.com/bar?foo=bar;#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar:#foo", {"https", "foo.com", "/bar", "?foo=bar%3A", "#foo", "https://foo.com/bar?foo=bar:#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar[#foo", {"https", "foo.com", "/bar", "?foo=bar%5B", "#foo", "https://foo.com/bar?foo=bar[#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar]#foo", {"https", "foo.com", "/bar", "?foo=bar%5D", "#foo", "https://foo.com/bar?foo=bar]#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar{#foo", {"https", "foo.com", "/bar", "?foo=bar%7B", "#foo", "https://foo.com/bar?foo=bar{#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar}#foo", {"https", "foo.com", "/bar", "?foo=bar%7D", "#foo", "https://foo.com/bar?foo=bar}#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar<#foo", {"https", "foo.com", "/bar", "?foo=bar%3C", "#foo", "https://foo.com/bar?foo=bar<#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar>#foo", {"https", "foo.com", "/bar", "?foo=bar%3E", "#foo", "https://foo.com/bar?foo=bar>#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar\\#foo", {"https", "foo.com", "/bar", "?foo=bar%5C", "#foo", "https://foo.com/bar?foo=bar\\#foo", 443 }, .None},
        {"https://foo.com/bar?foo=bar^#foo", {"https", "foo.com", "/bar", "?foo=bar%5E", "#foo", "https://foo.com/bar?foo=bar^#foo", 443}, .None},
        {"https://foo.com/bar?foo=bar`#foo", {"https", "foo.com", "/bar", "?foo=bar%60", "#foo", "https://foo.com/bar?foo=bar`#foo", 443}, .None},
        {`https://foo.com/bar?foo=bar"#foo`, {"https", "foo.com", "/bar", "?foo=bar%22", "#foo", `https://foo.com/bar?foo=bar"#foo`, 443}, .None},
        {"https://foo.com/bar?foo=bar", {"https", "foo.com", "/bar", "?foo=bar", "", "https://foo.com/bar?foo=bar", 443}, .None},
        {"https://foo.com/bar#foo", {"https", "foo.com", "/bar", "", "#foo", "https://foo.com/bar#foo", 443}, .None},
        {"https://foo.com/bar", {"https", "foo.com", "/bar", "", "", "https://foo.com/bar", 443}, .None},
        {"https://foo.com/", {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, .None},
        {"https://foo.com?foo=bar", {"https", "foo.com", "", "?foo=bar", "", "https://foo.com?foo=bar", 443}, .None},
        {"https://foo.com#foo", {"https", "foo.com", "", "", "#foo", "https://foo.com#foo", 443}, .None},
        {"0https://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"+https://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"-https://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {".https://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {" https://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"ht tps://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"ht_tps://foo.com/bar?foo=bar#foo", {}, .Scheme_Not_Found},
        {"ws://foo.com/bar?foo=bar#foo", {}, .Invalid_Scheme},
        {"https://.foo.com/bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://foo.com./bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://-foo.com/bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://foo.com-/bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://foo/bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://f oo.com/bar?foo=bar#foo", {}, .Host_Not_Found},
        {"https://f_oo.com/bar?foo=bar#foo", {}, .Host_Not_Found},
    }
    for test, _ in tests {
        res, err := parse_url(test.str)
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, err, test.err)
    }
}

@(test)
test_build_request :: proc(t: ^testing.T) {
    headers_a := make(map[string]string)
    defer delete(headers_a)
    headers_a["Connection"] = "close"

    headers_b := make(map[string]string)
    defer delete(headers_b)
    headers_b["Connection"] = ""

    tests := []struct{method: Method, url: Url, headers: map[string]string, body, res: string}{
        {.Post, {"http", "foo.com", "/", "", "", "http://foo.com/", 80}, nil, "", "POST / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Post, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "POST / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Post, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, `{"foo": "bar"}`, "POST / HTTP/1.1\r\nHost: foo.com\r\n\r\n" + `{"foo": "bar"}`},
        {.Get, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "GET / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Get, {"https", "foo.com", "/bar", "", "", "https://foo.com/bar", 443}, nil, "", "GET /bar HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Get, {"https", "foo.com", "/bar", "?foo=bar", "", "https://foo.com/bar?foo=bar", 443}, nil, "", "GET /bar?foo=bar HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Get, {"https", "foo.com", "/bar", "?foo=bar", "#foo", "https://foo.com/bar?foo=bar#foo", 443}, nil, "", "GET /bar?foo=bar#foo HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Get, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, headers_a, "", "GET / HTTP/1.1\r\nHost: foo.com\r\nConnection: close\r\n\r\n"},
        {.Get, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, headers_b, "", "GET / HTTP/1.1\r\nHost: foo.com\r\nConnection: \r\n\r\n"},
        {.Put, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "PUT / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Patch, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "PATCH / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Delete, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "DELETE / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Head, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "HEAD / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
        {.Options, {"https", "foo.com", "/", "", "", "https://foo.com/", 443}, nil, "", "OPTIONS / HTTP/1.1\r\nHost: foo.com\r\n\r\n"},
    }
    for test, _ in tests {
        res := _build_request(test.method, test.url, test.headers, transmute([]u8)test.body)
        testing.expect_value(t, string(res), test.res)
    }
}

@(test)
test_parse_response :: proc(t: ^testing.T) {
    body : string : `{"foo": "bar"}`

    headers_a := make(map[string]string)
    defer delete(headers_a)
    headers_a["Host"] = "foo.com"
    headers_a["Connection"] = "close"

    headers_b := make(map[string]string)
    defer delete(headers_b)
    headers_b["Host"] = "foo.com"
    headers_b["Connection"] = ""

    tests := []struct{buf: string, res: ^Response, err: Parse_Error}{
        {"HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\n\r\n" + body, &{headers_a, "HTTP/1.1", "OK", transmute([]u8)body, 200}, .None},
        {"HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: close\r\n\r\n", &{headers_a, "HTTP/1.1", "OK", {}, 200}, .None},
        {"HTTP/1.1 200 OK\r\nHost: foo.com\r\nConnection: \r\n\r\n", &{headers_b, "HTTP/1.1", "OK", {}, 200}, .None},
        {"HTTP/1.1 200 OK\r\n\r\n", &{nil, "HTTP/1.1", "OK", {}, 200}, .None},
        {"Host: foo.com\r\nConnection: close\r\n\r\n", nil, .Status_Line_Not_Found},
        {"HTTP/1.1 200\r\nHost: foo.com\r\nConnection: close\r\n\r\n", nil, .Invalid_Status_Line},
        {"HTTP/1.1 200 OK\r\nHost: foo.com\r\n: close\r\n\r\n", nil, .Invalid_Header},
        {"HTTP/1.1 200 OK\r\nHost: foo.com\r\n:\r\n\r\n", nil, .Invalid_Header},
    }
    for test, _ in tests {
        res, err := _parse_response(transmute([]u8)test.buf)
        defer delete(res.headers)
        defer free(res)

        if res != nil {
            for key, val in res.headers {
                testing.expect_value(t, val, test.res.headers[key])
            }
            testing.expect_value(t, res.version, test.res.version)
            testing.expect_value(t, res.reason, test.res.reason)
            testing.expect_value(t, string(res.body), string(test.res.body))
            testing.expect_value(t, res.status, test.res.status)
            continue
        }
        testing.expect_value(t, res, test.res)
        testing.expect_value(t, err, test.err)
    }
}
