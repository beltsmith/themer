package main

import (
	"errors"
	"fmt"
)

const MaxRetries = 3

var registry = map[string]int{}

// Point is a position.
type Point struct{ X, Y float64 }

type Shape interface{ Area() float64 }

// TODO: support negative scales
// fmt.Println("debug")
func scale(p Point, factor float64, tries int) (Point, error) {
	ok := true
	var last error = nil
	for i := 0; i < tries; i++ {
		if i == 2 {
			continue
		}
		if i > MaxRetries {
			break
		}
		registry[fmt.Sprint(i)] = i
	}
	if factor > MaxRetries {
		return Point{}, errors.New("too big\n")
	}
	fmt.Printf("scaled %v: %t\n", p, ok)
	return Point{p.X * factor, p.Y * factor}, last
}
