package com.debridmusic.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * Minimal, dependency-free crash screen (plain Android views, no Hilt/Compose) so
 * it cannot itself fail. Runs in its own process (see manifest) and shows the
 * captured stack trace with a copy/share button.
 */
class CrashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val trace = intent.getStringExtra(CrashReporter.EXTRA_TRACE)
            ?: runCatching { CrashReporter.crashFile(application).readText() }.getOrNull()
            ?: "Geen crashdetails beschikbaar."

        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#121212"))
            setPadding(pad, pad, pad, pad)
        }

        root.addView(TextView(this).apply {
            text = "De app is gecrasht"
            setTextColor(Color.parseColor("#FF6E6E"))
            textSize = 20f
            setTypeface(typeface, Typeface.BOLD)
        })
        root.addView(TextView(this).apply {
            text = "Maak een screenshot van dit scherm of tik op Kopieer en stuur het door."
            setTextColor(Color.parseColor("#BBBBBB"))
            textSize = 13f
            setPadding(0, pad / 2, 0, pad / 2)
        })

        val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        buttons.addView(Button(this).apply {
            text = "Kopieer"
            setOnClickListener {
                val cb = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cb.setPrimaryClip(ClipData.newPlainText("crash", trace))
                Toast.makeText(this@CrashActivity, "Gekopieerd", Toast.LENGTH_SHORT).show()
            }
        })
        buttons.addView(Button(this).apply {
            text = "Deel"
            setOnClickListener {
                val share = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, trace)
                }
                runCatching { startActivity(Intent.createChooser(share, "Crash delen")) }
            }
        })
        buttons.addView(Button(this).apply {
            text = "Sluiten"
            setOnClickListener { finishAffinity() }
        })
        root.addView(buttons)

        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        scroll.addView(TextView(this).apply {
            text = trace
            setTextColor(Color.parseColor("#E0E0E0"))
            typeface = Typeface.MONOSPACE
            textSize = 11f
            setTextIsSelectable(true)
            setPadding(0, pad, 0, pad)
            gravity = Gravity.TOP
        })
        root.addView(scroll)

        setContentView(root)
    }
}
