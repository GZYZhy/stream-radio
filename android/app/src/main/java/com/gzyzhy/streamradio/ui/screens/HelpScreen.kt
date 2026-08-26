package com.gzyzhy.streamradio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.gzyzhy.streamradio.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.help_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item { SectionHeader(stringResource(R.string.help_getting_started)) }
            item { HelpItem(stringResource(R.string.help_play), stringResource(R.string.help_play_desc)) }
            item { HelpItem(stringResource(R.string.help_search), stringResource(R.string.help_search_desc)) }
            item { HelpItem(stringResource(R.string.help_program_info), stringResource(R.string.help_program_info_desc)) }

            item { SectionHeader(stringResource(R.string.help_station_mgmt)) }
            item { HelpItem(stringResource(R.string.help_add_station), stringResource(R.string.help_add_station_desc)) }
            item { HelpItem(stringResource(R.string.help_import_local), stringResource(R.string.help_import_desc)) }
            item { HelpItem(stringResource(R.string.help_long_press), stringResource(R.string.help_long_press_desc)) }
            item { HelpItem(stringResource(R.string.help_swipe_left), stringResource(R.string.help_swipe_left_desc)) }

            item { SectionHeader(stringResource(R.string.help_favorites)) }
            item { HelpItem(stringResource(R.string.help_favorite), stringResource(R.string.help_favorite_desc)) }
            item { HelpItem(stringResource(R.string.help_favorites_list), stringResource(R.string.help_favorites_list_desc)) }

            item { SectionHeader(stringResource(R.string.help_subscriptions)) }
            item { HelpItem(stringResource(R.string.help_sub_entry), stringResource(R.string.help_sub_entry_desc)) }
            item { HelpItem(stringResource(R.string.help_sub_add), stringResource(R.string.help_sub_add_desc)) }
            item { HelpItem(stringResource(R.string.help_sub_manual_sync), stringResource(R.string.help_sub_manual_sync_desc)) }
            item { HelpItem(stringResource(R.string.help_sub_auto_sync), stringResource(R.string.help_sub_auto_sync_desc)) }
            item { HelpItem(stringResource(R.string.help_sub_note), stringResource(R.string.help_sub_note_desc)) }

            item { SectionHeader(stringResource(R.string.help_network)) }
            item { HelpItem(stringResource(R.string.help_connectivity_check), stringResource(R.string.help_connectivity_check_desc)) }
            item { HelpItem(stringResource(R.string.help_delete_station), stringResource(R.string.help_delete_desc)) }
            item { HelpItem(stringResource(R.string.help_network_note), stringResource(R.string.help_network_note_desc)) }

            item { SectionHeader(stringResource(R.string.help_appearance_other)) }
            item { HelpItem(stringResource(R.string.help_theme), stringResource(R.string.help_theme_desc)) }
            item { HelpItem(stringResource(R.string.help_background_playback), stringResource(R.string.help_background_playback_desc)) }
            item { HelpItem(stringResource(R.string.help_quality_indicator), stringResource(R.string.help_quality_indicator_desc)) }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun HelpItem(title: String, desc: String) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(desc, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    )
}
