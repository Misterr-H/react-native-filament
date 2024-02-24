package com.margelo.filament;

import android.view.Choreographer;

import androidx.annotation.Keep;

import com.facebook.jni.HybridData;
import com.facebook.proguard.annotations.DoNotStrip;

/** @noinspection JavaJniMissingFunction*/
public class FilamentChoreographer {
    /** @noinspection unused, FieldCanBeLocal */
    @DoNotStrip
    @Keep
    private final HybridData mHybridData;
    private final Choreographer choreographer;
    private boolean isRunning;

    public FilamentChoreographer() {
        mHybridData = initHybrid();
        choreographer = Choreographer.getInstance();
    }

    private void onFrameCallback(long timestamp) {
        if (!isRunning) return;
        onFrame(timestamp);
        choreographer.postFrameCallback(this::onFrameCallback);
    }

    /** @noinspection unused */
    @DoNotStrip
    @Keep
    private synchronized void start() {
        if (!isRunning) {
            isRunning = true;
            choreographer.postFrameCallback(this::onFrameCallback);
        }
    }

    /** @noinspection unused */
    @DoNotStrip
    @Keep
    private synchronized void stop() {
        if (isRunning) {
            isRunning = false;
            choreographer.removeFrameCallback(this::onFrameCallback);
        }
    }

    private native HybridData initHybrid();
    private native void onFrame(long timestamp);
}