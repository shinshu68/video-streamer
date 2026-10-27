package library

import (
	"io/fs"
	"syscall"
)

// hasHiddenOrSystemAttr は Windows の隠し属性かシステム属性が付いているかを返す。
func hasHiddenOrSystemAttr(fi fs.FileInfo) bool {
	data, ok := fi.Sys().(*syscall.Win32FileAttributeData)
	if !ok {
		return false
	}
	return data.FileAttributes&(syscall.FILE_ATTRIBUTE_HIDDEN|syscall.FILE_ATTRIBUTE_SYSTEM) != 0
}
