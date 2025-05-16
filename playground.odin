package main

import "core:strings"
import "core:testing"
import "core:log"

HttpUrl :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    query:      string,
    fragment:   string,
}

/*
Reports whether `s` contains any ASCII control character

Inputs:
- s: The input string

Returns:
- ok: A boolean indicating if any ASCII control character was found
*/
@(private)
_string_contains_control_character :: proc(s: string) -> (ok: bool) {
    for _, i in s {
        if s[i] < ' ' || s[i] == 0x7f {
            return true
        } 
    }
    return false
}

/*
Extracts the scheme part from `raw_url`

Inputs:
- raw_url: The input string

Returns:
- res: The scheme
- remainder: The rest of the string
- ok: A boolean indicating whether the scheme was found or not
*/
@(private)
_extract_scheme_from_url :: proc(raw_url: string) -> (res, remainder: string, ok: bool) {
    for c, i in raw_url {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z':
            continue

        case '0' <= c && c <= '9' || c == '+' || c == '-' || c == '.':
            if i == 0 {
                // [0-9+-.] found at the beginning
                return "", raw_url, false
            }

        case c == ':':
            if i == 0 {
                // colon found at the beginning
                return "", raw_url, false
            }
            return raw_url[:i], raw_url[i+1:], true

        case:
            // invalid character found
            return "", raw_url, false
        }
    }
    return "", raw_url, false
}

/*
Extracts the host part from `raw_url`

Inputs:
- raw_url: The input string

Returns:
- res: The host
- remainder: The rest of the string
- ok: A boolean indicating whether the host was found or not
*/
@(private)
_extract_host_from_url :: proc(raw_url: string) -> (res, remainder: string, ok: bool) {
    url := strings.trim_prefix(raw_url, "//")
    hyphen_pos, period_pos: int

    for c, i in url {
        switch {
        case 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9':
            continue

        case c == '-':
            if i == 0 || i == len(url)-1 {
                // hyphen found at the beginning or end
                return "", raw_url, false
            }
            hyphen_pos = i

        case c == '.':
            if i == 0 || i == len(url)-1 {
                // period found at the beginning or end
                return "", raw_url, false
            }
            period_pos = i

        case c == '/':
            if i == 0 || hyphen_pos == i-1 || period_pos == i-1 {
                // slash found at the beginning or after hyphen/period
                return "", raw_url, false
            }

            if period_pos != 0 {
                return url[:i], url[i:], true
            }

        case:
            // invalid character found        
            return "", raw_url, false
        }
    }
    return "", raw_url, false
}

/*
Escapes specific characters from `raw_url` using percent-encoding

Inputs:
- raw_url: The input string

Returns:
- res: The percent-encoded url 
*/
@(private)
_percent_encode_url :: proc(raw_url: string) -> (res: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    for c, i in raw_url {
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

@(private)
_extract_path_query_fragment :: proc(raw_url: string) -> (path, query, fragment: string) {
    query_pos := strings.index(raw_url, "?")
    fragment_pos := strings.index(raw_url, "#")

    switch {
    case query_pos != -1 && fragment_pos != -1:
        // query and fragment are present
        path = strings.cut(raw_url, 0, query_pos)
        fragment = strings.cut(raw_url, fragment_pos, 0)
        query = strings.cut(raw_url, query_pos, len(raw_url)-len(path)-len(fragment))

    case query_pos != -1 && fragment_pos == -1:
        // query is present but not fragment
        path = strings.cut(raw_url, 0, query_pos)
        query = strings.cut(raw_url, query_pos, 0)

    case query_pos == -1 && fragment_pos != -1:
        // fragment is present but not query
        path = strings.cut(raw_url, 0, fragment_pos)
        fragment = strings.cut(raw_url, fragment_pos, 0)

    case:
        // neither query nor fragment are present
        path = raw_url
    }
    return path, query, fragment
}

Parse_Error :: enum i32 {
    None,
    // Found an ASCII control character.
    Found_Control_Character,
    // Unable to extract scheme part of http url.
    Scheme_Not_Found,
    // Scheme is neither `http` nor `https`.
    Invalid_Scheme,
    // Unable to extract host part of http url.
    Host_Not_Found,
}

parse_http_url :: proc(raw_url: string) -> (res: HttpUrl, err: Parse_Error) {
    ok := _string_contains_control_character(raw_url)
    if ok {
        return HttpUrl{}, Parse_Error.Found_Control_Character
    }

    remainder: string
    res.scheme, remainder, ok = _extract_scheme_from_url(raw_url)
    if !ok {
        return HttpUrl{}, Parse_Error.Scheme_Not_Found   
    }
    if res.scheme != "http" && res.scheme != "https" {
        return HttpUrl{}, Parse_Error.Invalid_Scheme
    }

    res.host, remainder, ok = _extract_host_from_url(remainder)
    if !ok {
        return HttpUrl{}, Parse_Error.Host_Not_Found
    }

    remainder = _percent_encode_url(remainder)
    res.path, res.query, res.fragment = _extract_path_query_fragment(remainder)
    return res, Parse_Error.None
}

@(test)
test_string_contains_control_character :: proc(t: ^testing.T) {
    ok := _string_contains_control_character("http://foo.com/bar?foo\nbar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http\r://foo.com/bar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo\x7f.com/bar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo.com/bar?foo&bar")
    testing.expect_value(t, ok, false)

    ok = _string_contains_control_character("http://foo.com/bar") 
    testing.expect_value(t, ok, false)
}

@(test)
test_extract_scheme_from_url :: proc(t: ^testing.T) {
    scheme, remainder, ok := _extract_scheme_from_url("http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "http")
    testing.expect_value(t, remainder, "//foo.com/bar?foo=bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("https://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "https")
    testing.expect_value(t, remainder, "//foo.com/bar?foo=bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("ssh://foo@bar")
    testing.expect_value(t, scheme, "ssh")
    testing.expect_value(t, remainder, "//foo@bar")
    testing.expect_value(t, ok, true)

    scheme, remainder, ok = _extract_scheme_from_url("0http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "0http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("+http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "+http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("-http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "-http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url(".http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, ".http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url(" http://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, " http://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("ht tp://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "ht tp://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    scheme, remainder, ok = _extract_scheme_from_url("ht_tp://foo.com/bar?foo=bar")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, remainder, "ht_tp://foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)
}

@(test)
test_extract_host_from_url :: proc(t: ^testing.T) {
    host, remainder, ok := _extract_host_from_url("//foo.com/bar?foo=bar")
    testing.expect_value(t, host, "foo.com")
    testing.expect_value(t, remainder, "/bar?foo=bar")
    testing.expect_value(t, ok, true)

    host, remainder, ok = _extract_host_from_url("//foo.com/foo/bar?foo=bar")
    testing.expect_value(t, host, "foo.com")
    testing.expect_value(t, remainder, "/foo/bar?foo=bar")
    testing.expect_value(t, ok, true)

    host, remainder, ok = _extract_host_from_url("//.foo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//.foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo.com./bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo.com./bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//-foo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//-foo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo.com-/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo.com-/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//foo/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//foo/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//f oo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//f oo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)

    host, remainder, ok = _extract_host_from_url("//f_oo.com/bar?foo=bar")
    testing.expect_value(t, host, "")
    testing.expect_value(t, remainder, "//f_oo.com/bar?foo=bar")
    testing.expect_value(t, ok, false)
}

@(test)
test_percent_encode_url :: proc(t: ^testing.T) {
    path := _percent_encode_url("/foo/bar?foo=bar")
    testing.expect_value(t, path, "/foo/bar?foo=bar")

    path = _percent_encode_url("/foo/bar?foo=123")
    testing.expect_value(t, path, "/foo/bar?foo=123")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz+123")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz+123")

    path = _percent_encode_url("/foo/bar?foo=bar&fizz=buzz#foo")
    testing.expect_value(t, path, "/foo/bar?foo=bar&fizz=buzz#foo")

    path = _percent_encode_url("/foo/bar-?foo=bar-")
    testing.expect_value(t, path, "/foo/bar-?foo=bar-")

    path = _percent_encode_url("/foo/bar_?foo=bar_")
    testing.expect_value(t, path, "/foo/bar_?foo=bar_")

    path = _percent_encode_url("/foo/bar.?foo=bar.")
    testing.expect_value(t, path, "/foo/bar.?foo=bar.")

    path = _percent_encode_url("/foo/bar~?foo=bar~")
    testing.expect_value(t, path, "/foo/bar~?foo=bar~")

    path = _percent_encode_url("/foo/bar ?foo=bar ")
    testing.expect_value(t, path, "/foo/bar%20?foo=bar%20")

    path = _percent_encode_url("/foo/bar;?foo=bar;")
    testing.expect_value(t, path, "/foo/bar%3B?foo=bar%3B")

    path = _percent_encode_url("/foo/bar:?foo=bar:")
    testing.expect_value(t, path, "/foo/bar%3A?foo=bar%3A")

    path = _percent_encode_url("/foo/bar[?foo=bar[")
    testing.expect_value(t, path, "/foo/bar%5B?foo=bar%5B")

    path = _percent_encode_url("/foo/bar]?foo=bar]")
    testing.expect_value(t, path, "/foo/bar%5D?foo=bar%5D")

    path = _percent_encode_url("/foo/bar{?foo=bar{")
    testing.expect_value(t, path, "/foo/bar%7B?foo=bar%7B")

    path = _percent_encode_url("/foo/bar}?foo=bar}")
    testing.expect_value(t, path, "/foo/bar%7D?foo=bar%7D")

    path = _percent_encode_url("/foo/bar<?foo=bar<")
    testing.expect_value(t, path, "/foo/bar%3C?foo=bar%3C")

    path = _percent_encode_url("/foo/bar>?foo=bar>")
    testing.expect_value(t, path, "/foo/bar%3E?foo=bar%3E")

    path = _percent_encode_url("/foo/bar\\?foo=bar\\",)
    testing.expect_value(t, path, "/foo/bar%5C?foo=bar%5C")

    path = _percent_encode_url("/foo/bar^?foo=bar^")
    testing.expect_value(t, path, "/foo/bar%5E?foo=bar%5E")

    path = _percent_encode_url("/foo/bar`?foo=bar`")
    testing.expect_value(t, path, "/foo/bar%60?foo=bar%60")

    path = _percent_encode_url(`/foo/bar"?foo=bar"`)
    testing.expect_value(t, path, "/foo/bar%22?foo=bar%22")
}

@(test)
test_parse_http_url :: proc(t: ^testing.T) {
    url, err := parse_http_url("http://foo.com/bar?foo=bar#foo")
    if err != Parse_Error.None {
        log.infof("err: %v\n", err) 
    }
    log.infof("url: %v\n", url)
}

/*
@(test)
test_parse_http_url :: proc(t: ^testing.T) {
    url, _ := parse_http_url("http://foo.com/bar?foo=bar#foo")
    log.infof("url: %v\n", url)
    defer free(url)

    url2, _ := parse_http_url("http://foo.com/bar?foo=bar")
    log.infof("url: %v\n", url2)
    defer free(url2)
    
    url3, _ := parse_http_url("http://foo.com/bar#foo")
    log.infof("url: %v\n", url3)
    defer free(url3)

    url4, _ := parse_http_url("http://foo.com/bar")
    log.infof("url: %v\n", url4)
    defer free(url4)

    url5, _ := parse_http_url("http://foo.com/")
    log.infof("url: %v\n", url5)
    defer free(url5)
}
*/
