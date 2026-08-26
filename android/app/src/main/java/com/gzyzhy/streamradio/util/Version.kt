package com.gzyzhy.streamradio.util

// 版本号比较：返回 1 表示 a>b，-1 表示 a<b，0 表示相等。
// 按「.」分段数字比较，正确处理 1.10 > 1.9（不能直接用字符串比较）
fun compareVersions(a: String, b: String): Int {
    fun parts(s: String): List<Int> {
        val cleaned = s.trim().removePrefix("v").removePrefix("V")
        return cleaned.split('.').map { it.toIntOrNull() ?: 0 }
    }
    val pa = parts(a)
    val pb = parts(b)
    val n = maxOf(pa.size, pb.size)
    // 缺位补 0 后逐段比较，如 1.6.1 > 1.6
    for (i in 0 until n) {
        val x = pa.getOrElse(i) { 0 }
        val y = pb.getOrElse(i) { 0 }
        if (x != y) return if (x > y) 1 else -1
    }
    return 0
}
