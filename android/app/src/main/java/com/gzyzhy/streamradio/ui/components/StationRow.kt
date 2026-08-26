package com.gzyzhy.streamradio.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.data.Station

@Composable
fun StationRow(
    station: Station,
    isCurrent: Boolean,
    onPlay: () -> Unit,
    onEdit: () -> Unit,
    onToggleFavorite: () -> Unit,
    onDelete: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    ListItem(
        modifier = Modifier.clickable { onPlay() },
        headlineContent = {
            Text(
                station.name,
                color = if (isCurrent) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurface
            )
        },
        supportingContent = {
            Text(
                station.url,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isCurrent) {
                    Text(
                        "▶",
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                }
                IconButton(onClick = onToggleFavorite) {
                    Icon(
                        if (station.isFavorite) Icons.Filled.Star else Icons.Outlined.Star,
                        contentDescription = "星标",
                        tint = if (station.isFavorite) MaterialTheme.colorScheme.tertiary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Box {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "更多")
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("编辑") },
                            onClick = { showMenu = false; onEdit() }
                        )
                        DropdownMenuItem(
                            text = { Text(if (station.isFavorite) "取消星标" else "标星") },
                            onClick = { showMenu = false; onToggleFavorite() }
                        )
                        DropdownMenuItem(
                            text = { Text("上移") },
                            onClick = { showMenu = false; onMoveUp() }
                        )
                        DropdownMenuItem(
                            text = { Text("下移") },
                            onClick = { showMenu = false; onMoveDown() }
                        )
                        Divider()
                        DropdownMenuItem(
                            text = { Text("删除", color = MaterialTheme.colorScheme.error) },
                            onClick = { showMenu = false; onDelete() }
                        )
                    }
                }
            }
        }
    )
}
