// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Buffered console log writer: timestamp prefix (HH:mm:ss.SSS), periodic HTTP POST to server.

package console

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	flushInterval = 5 * time.Second
	timeFormat    = "15:04:05.000"
)

// Writer buffers output, prefixes each line with timestamp, and flushes to server via HTTP POST.
type Writer struct {
	mu       sync.Mutex
	buf      bytes.Buffer
	client   *http.Client
	postURL  string // Resolved full URL for POST
	stop     chan struct{}
	stopped  chan struct{}
	writeCh  chan []byte
	prefixFn func() []byte
}

// NewWriter creates a console writer that POSTs to consoleURL (resolved against baseURL if relative).
func NewWriter(client *http.Client, baseURL *url.URL, consoleURL string) (*Writer, error) {
	postURL, err := resolveURL(baseURL, consoleURL)
	if err != nil {
		return nil, err
	}
	w := &Writer{
		client:   client,
		postURL:  postURL,
		stop:     make(chan struct{}),
		stopped:  make(chan struct{}),
		writeCh:  make(chan []byte, 64),
		prefixFn: timestampPrefix,
	}
	go w.flushLoop()
	return w, nil
}

func timestampPrefix() []byte {
	return []byte(time.Now().Format(timeFormat) + " ")
}

func resolveURL(base *url.URL, consoleURL string) (string, error) {
	if consoleURL == "" {
		return "", fmt.Errorf("console URL is empty")
	}
	if strings.HasPrefix(consoleURL, "http://") || strings.HasPrefix(consoleURL, "https://") {
		return consoleURL, nil
	}
	path := consoleURL
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	u := &url.URL{Scheme: base.Scheme, Host: base.Host, Path: path}
	return u.String(), nil
}

// Write implements io.Writer. Each line is prefixed with timestamp before buffering.
func (w *Writer) Write(p []byte) (n int, err error) {
	if len(p) == 0 {
		return 0, nil
	}
	// Copy so caller's buffer can be reused
	b := make([]byte, len(p))
	copy(b, p)
	select {
	case w.writeCh <- b:
		return len(p), nil
	case <-w.stop:
		return 0, io.ErrClosedPipe
	}
}

// Close stops the flush loop and flushes remaining data.
func (w *Writer) Close() error {
	close(w.stop)
	<-w.stopped
	return nil
}

func (w *Writer) flushLoop() {
	defer close(w.stopped)
	tick := time.NewTicker(flushInterval)
	defer tick.Stop()
	for {
		select {
		case <-w.stop:
			w.flush()
			return
		case data, ok := <-w.writeCh:
			if !ok {
				return
			}
			w.mu.Lock()
			w.buf.Write(w.prefixFn())
			w.buf.Write(data)
			if !bytes.HasSuffix(data, []byte("\n")) {
				w.buf.WriteByte('\n')
			}
			w.mu.Unlock()
		case <-tick.C:
			w.flush()
		}
	}
}

func (w *Writer) flush() {
	w.mu.Lock()
	if w.buf.Len() == 0 {
		w.mu.Unlock()
		return
	}
	data := w.buf.Bytes()
	body := make([]byte, len(data))
	copy(body, data)
	w.buf.Reset()
	w.mu.Unlock()

	req, err := http.NewRequest(http.MethodPost, w.postURL, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	resp, err := w.client.Do(req)
	if err != nil {
		return
	}
	resp.Body.Close()
}
