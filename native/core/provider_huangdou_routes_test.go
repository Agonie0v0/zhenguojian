package core

import (
	"context"
	"crypto/x509"
	"net/http"
	"reflect"
	"testing"
)

func TestHuangdouRecoversExpiredRememberedHost(t *testing.T) {
	var hosts []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		hosts = append(hosts, request.URL.Hostname())
		if request.URL.Hostname() == "xqjurgek.top" {
			return nil, x509.CertificateInvalidError{Cert: &x509.Certificate{}, Reason: x509.Expired}
		}
		if request.Header.Get("Origin") != huangdouBaseURL || request.Header.Get("Referer") != huangdouBaseURL+"/home" || request.Header.Get("sign") == "" {
			t.Fatal("fallback lost its source headers or signature")
		}
		return sourceFixtureResponse(request, 200, `{"status":"y","data":{"list":[]}}`), nil
	})
	d.proxyRouter = &proxyRouter{mode: "direct"}
	d.providerHosts[sourceHuangdou] = "https://xqjurgek.top"
	client := newHuangdouAPIClient(d)
	var result any
	if err := client.call(context.Background(), "/drama/list", nil, &result); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(hosts, []string{"xqjurgek.top", "dptewvxi.top"}) || d.providerHosts[sourceHuangdou] != huangdouBaseURL || result == nil {
		t.Fatalf("failed to recover old host: %v", hosts)
	}
	if canonicalProviderSource("dptewvxi.top") != sourceHuangdou || providerSourceForURL(huangdouBaseURL+"/api/drama/play") != sourceHuangdou {
		t.Fatal("new host was not recognized as huangdou")
	}
}

func TestHuangdouPreservesCustomHostAndAccessErrors(t *testing.T) {
	for _, custom := range []bool{false, true} {
		t.Run(map[bool]string{false: "access", true: "custom"}[custom], func(t *testing.T) {
			calls := 0
			d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
				calls++
				if custom {
					if request.URL.Host != "custom.test" {
						t.Fatal("custom source escaped its host")
					}
					return nil, x509.CertificateInvalidError{Cert: &x509.Certificate{}, Reason: x509.Expired}
				}
				return sourceFixtureResponse(request, 200, `{"status":"n","errorCode":"813004","msg":"access denied"}`), nil
			})
			d.proxyRouter = &proxyRouter{mode: "direct"}
			if custom {
				d.cfg.HuangdouURL = "https://custom.test"
			}
			if err := newHuangdouAPIClient(d).call(context.Background(), "/drama/play", nil, nil); err == nil || calls != 1 {
				t.Fatalf("error or retry count changed: calls=%d err=%v", calls, err)
			}
		})
	}
}
