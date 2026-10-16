---
source: https://docs.example/table-code.html
clipped: 2026-10-16
---
# Sorting in place

Three ways to sort an array without making a copy, and what each costs.

| Method | Average | Stable |
| --- | ---: | --- |
| Insertion | O(n²) | yes |
| Heap | O(n log n) | no |
| Quick \| median of three | O(n log n) | no |

## A table with no heading row

| Monday | Water the beds | |
| --- | --- | --- |
| Tuesday | Rest | |

## A table with code and a list in its cells

| Call | Notes |
| --- | --- |
| `arr.sort()` | sorts in place; returns the array |

## Code

```js
function insertionSort(a) {
  for (let i = 1; i < a.length; i++) {
    let j = i;
    while (j > 0 && a[j - 1] > a[j]) { [a[j - 1], a[j]] = [a[j], a[j - 1]]; j--; }
  }
  return a;
}
```

```python
def heap_sort(a):
    heapq.heapify(a)
    return [heapq.heappop(a) for _ in range(len(a))]
```

````rust
fn main() { println!("```"); }
````

## Checklist

- [x] Read the paper
- [ ] Try it on real data

The old way was ~~bubble sort~~ and it is gone. See [the heap notes](https://docs.example/docs/heap.html) and \[\[not a link]] in passing.
