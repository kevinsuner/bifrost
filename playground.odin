package main

import "core:strings"
import "core:testing"

HttpUrl :: struct {
    scheme: string,
    host:   string,
    path:   string,
    query:  string,
}

// [scheme]://[host]/[path]?[query]
//
// [scheme] = http | https  ✓
// [host] = example.com     ×
// [path] = foo             ×
// [query] = ?foo=bar       ×


// Reports whether str contains any ASCII control character. 
_string_contains_control_character :: proc(str: string) -> bool {
    for _, idx in str {
        if str[idx] < ' ' || str[idx] == 0x7f {
            return true
        }
    }
    return false
}

// Provided url can be in the form of scheme:path, if so, return scheme and remainder,
// otherwise return empty string and remainder. Scheme must be ([a-zA-Z][a-zA-Z0-9+-.]*).
_extract_scheme_from_url :: proc(raw_url: string) -> (scheme, remainder: string, ok: bool) {
    for char, idx in raw_url {
        switch {
        case 'a' <= char && char <= 'z' || 'A' <= char && char <= 'Z':
            continue

        case '0' <= char && char <= '9' || char == '+' || char == '-' || char == '.': 
            // [0-9+-.] found at the beginning
            if idx == 0 {
                return "", raw_url, false
            }
            
        case char == ':':
            if idx == 0 {
                // colon found at the beginning
                return "", raw_url, false
            }
            return raw_url[:idx], raw_url[idx+1:], true

        case:
            // invalid character found
            return "", raw_url, false
        }
    }
    return "", raw_url, false
}

_extract_host_from_url :: proc(raw_url: string) -> (host, remainder: string, ok: bool) {
    url := strings.trim_prefix(raw_url, "//")
    tld_idx, hyphen_idx: int

    for char, idx in url {
        switch {
        case 'a' <= char && char <= 'z' || 'A' <= char && char <= 'Z' || '0' <= char && char <= '9':
            continue

        case char == '-':
            if idx == 0 || idx == len(url)-1 {
                // hyphen found at the beginning or end 
                return "", url, false 
            }
            hyphen_idx = idx

        case char == '.':
            if idx == 0 || idx == len(url)-1 {
                // dot found at the beginning or end
                return "", url, false
            }
            tld_idx = idx

        case char == '/':
            if idx == 0 || hyphen_idx == idx-1 || tld_idx == idx-1 {
                // slash found at the beginning or after hyphen/dot
                return "", url, false
            }

            if tld_idx != 0 {
                return url[:idx], url[idx+1:], true
            }

        case:
            // invalid character found
            return "", url, false
        }
    }
    return "", url, false
}

@(test)
test_string_contains_control_character :: proc(t: ^testing.T) {
    ok := _string_contains_control_character("http://foo.com/?foo\nbar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http\r://foo.com/")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo\x7f.com/")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo.com/?foo&bar")
    testing.expect_value(t, ok, false)

    ok = _string_contains_control_character("http://foo.com/") 
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
    testing.expect_value(t, remainder, "bar?foo=bar")
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
}





















