
# Cangjie 语言基础发育

## 1. cangjie语言在定义function时，前缀为func，不要定义为fn或者function

## 2. cangjie语言在定义main函数时，无前缀

## 3. cangjie语言在循环对字符串进行操作时，提倡使用for (i in 0..s.size) {}，不要使用for (i in 0..s.length) {}

## 4. cangjie语言在取字符串时，应使用s[start,end]的方式，不要使用s.subString(start,end)

## 5. String 语法
字符串遍历与字符处理，处理多语言或特殊字符时将字符视为Rune值操作，示例代码：
```cangjie
func isLowerWord(s: String) {
    for (ch in s) {
        let runeCh = Rune(ch)
        if (runeCh < r'a' || runeCh > r'z') {
            return false
        }
    }
    return true
}
```

字符串初始化与多行文本，根据内容和格式需求选择合适方式，示例代码：
单行字符串：
```cangjie
let s2 = 'Hello ```cangjie Lang'

多行字符串：
```cangjie
let s6 = '''
    Hello,
    cangjie Lang'''
```
原始字符串：
```cangjie
let s9 = ###"
    Hello,
    C```cangjie
    Lang"###
```
字符串拼接与格式化，拼接列表用String.join，构建复杂动态字符串用插值，示例代码：
列表拼接：
```cangjie
let joinedString = String.join(["a", "b", "c"], delimiter: ",") // a,b,c
```
动态格式化：
```cangjie
let fruit = "apples"
let count = 10
let interpolatedString = "There are ${count * count} ${fruit}" // There are 100 apples
```
用户自定义类型与字符串表示，需在 UI 显示或日志输出的自定义类型应实现ToString接口，示例代码：
```cangjie
class Point <: ToString {
    let x: Int64
    let y: Int64
    public init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }
    public func toString(): String {
        "Point(${this.x}, ${this.y})"
    }
}
```
类型转换与解析，正确进行字符串与其他基本数据类型转换，示例代码：
基本类型转字符串：
```cangjie
let N = 123
let strN = N.toString() // strN = "123"
```
字符串转基本类型：
```cangjie
import std.convert.*
main() {
    let v = Int64.parse("123") // v = 123 (Int64)
}
```
字符串切片与子串获取，使用范围索引[start..end]提取子串，示例代码：
```cangjie
main() {
    let words = "Hello, World"
    println(words[2..])  // llo, World
    println(words[..5])  // Hello
    println(words[2..5])  // llo
    println(words[2..=5]) // llo,
}
```
字符串到 Rune 数组转换，根据需求选择转换方式，示例代码：
```cangjie
import std.collection.*
main() {
    let s = "hello"
    let arr = s.toRuneArray() // arr = [h, e, l, l, o]
    println(arr[1]) // e

    for (c in s.runes()) {
        print("${c} ") // h e l l o
    }
    println(s.runes() |> filter {c => c == r'l'} |> count) // 2
}
```
## 6. Collection 语法
声明式集合操作与数据流，利用高阶函数和管道操作符处理集合，示例代码：
转换 (Map)：
```cangjie
let squaredArr = collectArray(arr |> map {x => x * x})
```
过滤 (Filter)：
```cangjie
let evenNumbers = collectArray(arr |> filter {x => x % 2 == 0})
```
聚合 (Fold/Reduce)：
```cangjie
let sum = arr |> fold(0) {old, curr => old + curr}
let reduceSum = (arr |> reduce {x, y => x + y}).getOrThrow()
```
精确表达逻辑条件与量词，使用all和any表达逻辑，正确表达蕴含关系，示例代码：
所有满足 (All)：
```cangjie
let allPositive = arr |> all {x => x > 0}
```
任一满足 (Any)：
```cangjie
let anyGreaterThanThree = arr |> any {x => x > 3}
```
逻辑蕴含 (Implication)：!(A) || B
集合统计与聚合，利用内置函数进行统计，示例代码：
计数 (Count)：
```cangjie
let rCount = s.runes() |> filter({c: Rune => c == r'r'}) |> count
```
最小值 (Min) 和最大值 (Max)：
```cangjie
let minVal = min(arr).getOrThrow()
let maxVal = max(arr).getOrThrow()
```
## 7. Function 语法
显式函数返回类型声明（针对循环体内的返回），函数含while循环且返回路径都在循环内时，需在循环外提供显式return语句，示例代码：
```cangjie
func whileLoopEx(n: Int64): Int64 {
    var counter = n
    var result = 1
    while (true) {
        if (counter <= 0) {
            return result
        }
        counter -= 1
        result *= 2
    }
    return 0      // 满足编译器类型检查
}
```
## 8. Hashmap 语法
明确类型定义与初始化，创建时明确键值类型，选择合适初始化方式，示例代码：
```cangjie
let a = HashMap<String, Int64>()  // 空HashMap，键为String，值为Int64
let b = HashMap<String, Int64>([("a", 0), ("b", 1), ("c", 2)]) // 从列表初始化
let d = HashMap<String, Int64>(10) // 指定初始容量
```
安全的元素访问与错误处理，避免直接访问可能不存在的键，使用get和getOrDefault，示例代码：
```cangjie
let map = HashMap<String, Int64>([("a", 0), ("b", 1), ("c", 2)])
let m = HashMap(("a", 1), ("b", 2))
println(m.get("a").getOrDefault({ => 0}))  // 输出: 1
println(m.get("c").getOrDefault({ => 0}))  // 输出: 0 (键'c'不存在时返回默认值0)
```
高效的迭代与基本操作，掌握遍历及增删改查操作，示例代码：
迭代：
```cangjie
let map = HashMap<String, Int64>([("a", 0), ("b", 1), ("c", 2)])
for ((k, v) in map) {
    println("The key is ${k}, the value is ${v}")
}
```
添加：
```cangjie
map.add("e", 4)
let map2 = HashMap<String, Int64>([("f", 5), ("g", 6)])
map.add(all: map2) // 批量添加
```
删除：
```cangjie
map.remove("g")
```
## 9. Hashset 语法
集合初始化与类型安全，根据需求选择初始化方式并明确元素类型，示例代码：
```cangjie
let emptySet = HashSet<String>()  // 空的String类型HashSet
let sizedSet = HashSet<Int64>(100)  // 容量为100的Int64类型HashSet
let initializedSet = HashSet<Int64>([0, 1, 2])  // 从数组初始化
```
元素高效管理与去重，利用特性进行元素操作，示例代码：
添加：
```cangjie
let mySet = HashSet<Int64>()
mySet.add(0)
let li = [2, 3]
mySet.add(all: li)
```
删除：
```cangjie
mySet.remove(1)
```
检查存在性：
```cangjie
let containsZero = mySet.contains(0)
```
数组与集合间的高效转换与数据清洗，利用collectHashSet函数，示例代码：
```cangjie
let arr: Array<Int64> = [1, 1, 2, 3, 3]
let uniqueSet: HashSet<Int64> = collectHashSet(arr) // 去重转为集合
let uniqueArr: Array<Int64> = collectHashSet(arr).toArray() // 去重转回数组
```

## 10. Rune 语法
Rune 字面量定义，以小写r为前缀，用单引号或双引号包裹，示例代码：
```cangjie
let a: Rune = r'a'
let b: Rune = r"b"
```
特殊字符与转义序列，用反斜杠\转义特殊字符，示例代码：
```cangjie
let slash: Rune = r'\\' // 单个反斜杠
let newLine: Rune = r'\n' // 换行符
```
Unicode 字符表示，用\u{}语法表示 Unicode 字符，示例代码：
```cangjie
let he: Rune = r'\u{4f60}' // 汉字 '你'
let llo: Rune = r'\u{597d}' // 汉字 '好'
```
Rune 类型操作限制，仅支持关系运算符，示例代码：
```cangjie
let r_a: Rune = r'a'
let r_b: Rune = r'b'
let isEqual = (r_a == r_b) // false
let isLess = (r_a < r_b)   // true
```
Rune 与 UInt32 的类型转换，可相互转换，示例代码：
```cangjie
let x: Rune = 'a'
let y: UInt32 = 65 // 'A'的Unicode值
let r1 = UInt32(x) // 97
let r2 = Rune(y)   // r'A'
```