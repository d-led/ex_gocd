// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"archive/zip"
	"crypto/md5"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFileMD5(t *testing.T) {
	tmp, err := os.CreateTemp("", "md5-test-*")
	require.NoError(t, err)
	defer os.Remove(tmp.Name())
	defer tmp.Close()

	content := "hello world"
	_, err = tmp.WriteString(content)
	require.NoError(t, err)
	_ = tmp.Close()

	expectedHash := md5.Sum([]byte(content))
	expectedHex := hex.EncodeToString(expectedHash[:])

	actualHex, err := fileMD5(tmp.Name())
	require.NoError(t, err)
	assert.Equal(t, expectedHex, actualHex)
}

func TestZipAndUnzipSecurely(t *testing.T) {
	// Create temporary directory for source files
	srcDir, err := os.MkdirTemp("", "zip-src-*")
	require.NoError(t, err)
	defer os.RemoveAll(srcDir)

	// Create test files
	file1Path := filepath.Join(srcDir, "file1.txt")
	err = os.WriteFile(file1Path, []byte("content of file 1"), 0644)
	require.NoError(t, err)

	subDir := filepath.Join(srcDir, "subdir")
	err = os.MkdirAll(subDir, 0755)
	require.NoError(t, err)

	file2Path := filepath.Join(subDir, "file2.txt")
	err = os.WriteFile(file2Path, []byte("content of file 2"), 0644)
	require.NoError(t, err)

	// Zip it
	zipPath, err := zipSource(srcDir)
	require.NoError(t, err)
	defer os.Remove(zipPath)

	// Unzip to a destination directory
	destDir, err := os.MkdirTemp("", "zip-dest-*")
	require.NoError(t, err)
	defer os.RemoveAll(destDir)

	err = unzipSecurely(zipPath, destDir)
	require.NoError(t, err)

	// Verify files extracted correctly
	f1Content, err := os.ReadFile(filepath.Join(destDir, "file1.txt"))
	require.NoError(t, err)
	assert.Equal(t, "content of file 1", string(f1Content))

	f2Content, err := os.ReadFile(filepath.Join(destDir, "subdir", "file2.txt"))
	require.NoError(t, err)
	assert.Equal(t, "content of file 2", string(f2Content))
}

func TestUnzipSecurelyZipSlipProtection(t *testing.T) {
	// Create a mock zip file that contains a Zip Slip entry (e.g. "../escaped.txt")
	tmpZip, err := os.CreateTemp("", "zipslip-*.zip")
	require.NoError(t, err)
	defer os.Remove(tmpZip.Name())
	defer tmpZip.Close()

	zw := zip.NewWriter(tmpZip)
	
	// Create malicious entry
	w, err := zw.Create("../escaped.txt")
	require.NoError(t, err)
	_, err = w.Write([]byte("malicious content"))
	require.NoError(t, err)

	err = zw.Close()
	require.NoError(t, err)
	_ = tmpZip.Close()

	// Target destination
	destDir, err := os.MkdirTemp("", "zipslip-dest-*")
	require.NoError(t, err)
	defer os.RemoveAll(destDir)

	// Unzip should return error and block extraction
	err = unzipSecurely(tmpZip.Name(), destDir)
	assert.Error(t, err)
	assert.True(t, strings.Contains(err.Error(), "Zip Slip") || strings.Contains(err.Error(), "boundary escape"), "Error should report Zip Slip detection")

	// Ensure malicious file was not written outside destDir
	escapedFilePath := filepath.Join(destDir, "../escaped.txt")
	_, err = os.Stat(escapedFilePath)
	assert.True(t, os.IsNotExist(err), "Malicious file should not exist")
}
