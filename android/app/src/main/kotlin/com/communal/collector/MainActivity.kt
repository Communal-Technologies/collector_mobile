package com.communal.collector

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    /**
     * FLAG_SECURE keeps the round out of the recents thumbnail and out of
     * screenshots. Locking the app when it goes to the background is worth little on
     * its own: the thumbnail the system keeps was taken while the takings, the float
     * and the member roster were still on screen. The member app is secure by
     * default for the same reason.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
