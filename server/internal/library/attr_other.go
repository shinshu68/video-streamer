//go:build !windows

package library

import "io/fs"

// hasHiddenOrSystemAttr は Windows 以外では属性を持たないため、常に false を返す。
func hasHiddenOrSystemAttr(fs.FileInfo) bool {
	return false
}
