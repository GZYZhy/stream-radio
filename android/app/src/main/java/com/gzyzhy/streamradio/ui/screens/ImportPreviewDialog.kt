package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.data.Station

// 导入预览对话框：勾选要导入的台
@Composable
fun ImportPreviewDialog(
    candidates: List<Station>,
    existingUrls: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (List<Station>) -> Unit
) {
    var selected by remember {
        mutableStateOf(
            candidates.filter { it.url !in existingUrls }.map { it.id }.toSet()
        )
    }

    val duplicateCount = candidates.count { it.url in existingUrls }
    val importableCount = candidates.size - duplicateCount

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("选择要导入的台") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                LazyColumn(modifier = Modifier.weight(1f, fill = false).heightIn(max = 400.dp)) {
                    items(candidates, key = { it.id }) { station ->
                        val exists = station.url in existingUrls
                        val checked = station.id in selected
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
                        ) {
                            Checkbox(
                                checked = checked,
                                onCheckedChange = { on ->
                                    selected = if (on) selected + station.id
                                    else selected - station.id
                                },
                                enabled = !exists
                            )
                            Spacer(Modifier.width(8.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(station.name,
                                    color = if (exists) MaterialTheme.colorScheme.onSurfaceVariant
                                    else LocalTextStyle.current.color)
                                Text(station.url,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1)
                            }
                            if (exists) {
                                Text("已存在",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "共 ${candidates.size} 个，可导入 $importableCount 个，重复 $duplicateCount 个",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm(candidates.filter { it.id in selected })
                },
                enabled = selected.isNotEmpty()
            ) { Text("导入 (${selected.size})") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}
