package com.nodecockpit.customization;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;

/** One bounded post-boot reconciliation when Vector misses the first SystemUI process. */
public final class BootRecoveryJobService extends JobService {
    private static final int JOB_ID=0x4e43;

    static void schedule(Context context) {
        JobScheduler scheduler=context.getSystemService(JobScheduler.class);
        if (scheduler==null) return;
        JobInfo job=new JobInfo.Builder(JOB_ID,new ComponentName(context,BootRecoveryJobService.class))
            .setMinimumLatency(45_000).setOverrideDeadline(75_000).build();
        scheduler.schedule(job);
    }

    @Override public boolean onStartJob(JobParameters params) {
        Thread worker=new Thread(() -> {
            try { LocalCustomization.recoverMissingBootHook(); }
            finally { jobFinished(params,false); }
        },"NodeCockpitBootRecovery");
        worker.start();
        return true;
    }

    @Override public boolean onStopJob(JobParameters params) { return false; }
}
