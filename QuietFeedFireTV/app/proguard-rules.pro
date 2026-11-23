# The page engine calls this object through addJavascriptInterface.
-keepclassmembers class app.quietfeed.firetv.PageBridge {
    @android.webkit.JavascriptInterface <methods>;
}
