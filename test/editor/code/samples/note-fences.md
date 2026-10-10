# Code in a note

A fence with a language:

```js
const answer = 42; // the answer
function ask(question) { return `${question}?`; }
```

A fence with no language:

```
plain text here
$x$ is not maths
```

One nobody knows:

```nosuchlanguage
still plain
```

An indented block:

    indented code

Tildes, and an info string with more after the name:

~~~python title="x.py"
def f(x): return x + 1
~~~

An unfinished fence:

```rust
fn main() { let x = 1; }
