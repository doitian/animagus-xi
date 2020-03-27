package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path"
	"strings"

	"github.com/golang/protobuf/proto"
	"github.com/xxuejie/animagus/pkg/ast"
)

func must(e error) {
	if e != nil {
		log.Fatal(e)
	}
}

func mustWriteln(w *bufio.Writer, line string) {
	_, err := w.WriteString(line)
	must(err)
	_, err = w.WriteString("\n")
	must(err)
}

func writeValue(w *bufio.Writer, id string, v *ast.Value) {
	primtive := ""
	switch v.GetT() {
	case ast.Value_UINT64, ast.Value_ARG, ast.Value_PARAM:
		primtive = fmt.Sprintf("(%v)", v.GetU())
	case ast.Value_BOOL:
		primtive = fmt.Sprintf("(%v)", v.GetB())
	case ast.Value_ERROR:
		primtive = fmt.Sprintf("(%v)", string(v.GetRaw()))
	case ast.Value_BYTES:
		primtive = fmt.Sprintf("(0x%x)", string(v.GetRaw()))
	}

	mustWriteln(w, fmt.Sprintf("%v [label=\"%v%v\"]", id, v.GetT(), primtive))
	for i, c := range v.GetChildren() {
		childID := fmt.Sprintf("%vc%v", id, i)
		mustWriteln(w, fmt.Sprintf("%v -> %v", id, childID))
		writeValue(w, childID, c)
	}
}

func writeCall(w *bufio.Writer, i int, c *ast.Call) {
	id := fmt.Sprintf("c%v", i)
	mustWriteln(w, fmt.Sprintf("subgraph cluster_%v {", id))

	mustWriteln(w, fmt.Sprintf("%v [label =\"%v\", shape=\"box\"]", id, c.GetName()))

	childID := fmt.Sprintf("%vv0", id)
	mustWriteln(w, fmt.Sprintf("%v -> %v", id, childID))
	writeValue(w, childID, c.GetResult())

	mustWriteln(w, "}")
}

func writeStream(w *bufio.Writer, i int, s *ast.Stream) {
	id := fmt.Sprintf("s%v", i)
	mustWriteln(w, fmt.Sprintf("%v [label=\"%v\", shape=\"box\"]", id, s.GetName()))

	childID := fmt.Sprintf("%vv0", id)
	mustWriteln(w, fmt.Sprintf("%v -> %v", id, childID))

	writeValue(w, childID, s.GetFilter())
}

func main() {
	if len(os.Args) < 3 {
		log.Fatal("usage: animagus-dot ast.bin ast.dot")
	}

	astContent, err := ioutil.ReadFile(os.Args[1])
	must(err)

	root := &ast.Root{}
	must(proto.Unmarshal(astContent, root))

	outFile, err := os.Create(os.Args[2])
	must(err)
	defer outFile.Close()

	astBase := path.Base(os.Args[1])
	astName := strings.TrimSuffix(astBase, path.Ext(astBase))

	w := bufio.NewWriter(outFile)
	mustWriteln(w, "digraph G {")
	mustWriteln(w, "newrank=\"true\"")
	mustWriteln(w, fmt.Sprintf("%v -> { streams  calls }\n", astName))
	for i, c := range root.Calls {
		mustWriteln(w, fmt.Sprintf("calls -> c%v", i))
		writeCall(w, i, c)
	}
	for i, s := range root.Streams {
		mustWriteln(w, fmt.Sprintf("streams -> s%v", i))
		writeStream(w, i, s)
	}
	mustWriteln(w, "}")

	w.Flush()
}
