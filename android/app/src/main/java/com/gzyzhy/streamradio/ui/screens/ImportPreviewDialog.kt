package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.R
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
        title = { Text(stringResource(R.string.import_preview_title)) },
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
                                Text(stringResource(R.string.import_already_exists),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.import_summary, candidates.size, importableCount, duplicateCount),
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
            ) { Text(stringResource(R.string.import_button, selected.size)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        }
    )
}
