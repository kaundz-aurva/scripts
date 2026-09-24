// gen_sfbench emits a production-shaped sensitive_fields corpus as COPY text on stdout.
// Usage: go run . -n 2500 -from 0 -to 357 [-tags] | psql -c "\copy sensitive_fields (...) FROM STDIN"
// Each datasource has its own RNG (seed, index), so any -from/-to split is byte-identical to a full run.
package main

import (
	"bufio"
	"encoding/hex"
	"flag"
	"fmt"
	"math/rand/v2"
	"os"
	"slices"
	"strings"
	"time"
)

// Tag ids match the tags table seeded by schema.sql: 1 Identity, 2 Financial, 3 Health, 4 Contact, 5 Technical.
var semanticTypes = []struct {
	name string
	risk int
	tag  int
}{
	{"country", 1, 4}, {"city", 2, 4}, {"latitude_longitude", 3, 4}, {"ip_address", 3, 5},
	{"email_address", 4, 4}, {"gnrp", 4, 3}, {"dob", 5, 3}, {"phone_number", 5, 4},
	{"jwt_token", 6, 5}, {"gstin_no", 6, 2}, {"upi_id", 6, 2}, {"voter_id", 7, 1},
	{"us_mbi", 7, 3}, {"driver_license", 8, 1}, {"us_driver_license", 8, 1}, {"us_itin", 8, 2},
	{"us_routing", 8, 2}, {"us_bank_number", 9, 2}, {"passport", 9, 1}, {"us_passport", 9, 1},
	{"pan_card", 9, 2}, {"ssn", 10, 1}, {"aadhaar_card", 10, 1}, {"cvv", 10, 2}, {"credit_card", 10, 2},
}

var baseTime = time.Date(2026, 9, 11, 3, 23, 54, 0, time.UTC)

func datasourceID(i int) string {
	return fmt.Sprintf("%08x-0000-4000-8000-%012x", i, i)
}

// rowsFor reproduces sfbench's three size tiers: first ~0.48% of datasources at 40x, next to 5% at 8x, rest 1x.
func rowsFor(i, n, base int) int {
	fat := max(1, (n*48+5000)/10000)
	mid := max(fat+1, (n*5+50)/100)
	switch {
	case i < fat:
		return base * 40
	case i < mid:
		return base * 8
	default:
		return base
	}
}

func sensitivity(risk int) int {
	switch {
	case risk >= 7:
		return 0
	case risk >= 5:
		return 1
	default:
		return 2
	}
}

func ts(t time.Time) string { return t.Format("2006-01-02 15:04:05+00") }

func genDatasource(w *bufio.Writer, i, n, base int, seed uint64, tags bool) {
	r := rand.New(rand.NewPCG(seed, uint64(i)))
	dsID := datasourceID(i)
	scanID := 1 + r.IntN(12)
	total := rowsFor(i, n, base)
	// Whole datasources are archived, never a fat one (sfbench: ~2% of rows, all in small/mid tiers).
	archived := r.Float64() < 0.02 && total < base*40
	created := baseTime.Add(time.Duration(i) * 10 * time.Second)
	createdS := ts(created)

	idBuf := make([]byte, 16)
	var types []int
	emitted := 0
	for tbl := 0; emitted < total; tbl++ {
		ncols := 20 + r.IntN(11)
		rowCount := 100 + r.IntN(4_999_900)
		for c := 0; c < ncols && emitted < total; c++ {
			emitted++
			for k := range idBuf {
				idBuf[k] = byte(r.Uint32())
			}
			h := hex.EncodeToString(idBuf)
			id := h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]

			var status string
			risk, conf := 0, 0
			types = types[:0]
			switch p := r.Float64(); {
			case p < 0.40:
				status = "skipped"
			case p < 0.75:
				status, conf = "confirmed", 80+r.IntN(21)
			case p < 0.98:
				status, conf = "pending", 40+r.IntN(40)
			default:
				status = "rejected"
			}
			if status == "confirmed" || status == "pending" {
				k := 1
				if p := r.Float64(); p >= 0.85 {
					k = 3
				} else if p >= 0.60 {
					k = 2
				}
				for len(types) < k {
					if t := r.IntN(len(semanticTypes)); !slices.Contains(types, t) {
						types = append(types, t)
					}
				}
				slices.SortFunc(types, func(a, b int) int { return strings.Compare(semanticTypes[a].name, semanticTypes[b].name) })
				for _, t := range types {
					risk = max(risk, semanticTypes[t].risk)
				}
			}
			deleted := `\N`
			if r.Float64() < 0.03 {
				deleted = ts(created.Add(-time.Duration(1+r.IntN(720)) * time.Hour))
			}
			dirty := r.Float64() < 0.04

			if tags {
				var seen [6]bool
				for _, t := range types {
					if tag := semanticTypes[t].tag; !seen[tag] {
						seen[tag] = true
						fmt.Fprintf(w, "%s\t%d\n", id, tag)
					}
				}
				continue
			}
			names := make([]string, len(types))
			for j, t := range types {
				names[j] = semanticTypes[t].name
			}
			fmt.Fprintf(w, "%s\t%s\t%d\t%s\t%d\t%d\t%d\t{%s}\tcol_%02d\ttbl_%06d\tdb_%03d\t%d\t%d\t%s\t%s\t%s\t%t\t%t\n",
				id, dsID, scanID, status, risk, sensitivity(risk), conf, strings.Join(names, ","),
				c, tbl, tbl/40, rowCount, created.Unix(), createdS, createdS, deleted, dirty, archived)
		}
	}
}

func main() {
	n := flag.Int("n", 2500, "total datasources in the corpus (drives size tiers)")
	from := flag.Int("from", 0, "first datasource index (inclusive)")
	to := flag.Int("to", -1, "last datasource index (exclusive, default n)")
	base := flag.Int("base", 9310, "rows in a small datasource; mid = 8x, fat = 40x")
	seed := flag.Uint64("seed", 42, "corpus seed")
	tags := flag.Bool("tags", false, "emit sensitivefield_tags (sensitive_field_id, tag_id) instead of sensitive_fields")
	flag.Parse()
	if *to < 0 || *to > *n {
		*to = *n
	}

	w := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer w.Flush()
	for i := *from; i < *to; i++ {
		genDatasource(w, i, *n, *base, *seed, *tags)
	}
}
