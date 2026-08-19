#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid = 0;
static volatile sig_atomic_t pending_signal = 0;
static volatile sig_atomic_t termination_deadline_armed = 0;
static volatile sig_atomic_t termination_requested = 0;
static const unsigned int termination_timeout_seconds = 5;

static void signal_child_group(pid_t pid, int signal_number) {
    if (kill(-pid, signal_number) == -1 && errno == ESRCH) {
        // The child establishes its process group before starting any helper.
        // A signal in that brief setup window must still reach the child.
        kill(pid, signal_number);
    }
}
static void arm_termination_deadline(void) {
    if (!termination_deadline_armed) {
        termination_deadline_armed = 1;
        alarm(termination_timeout_seconds);
    }
}

static void force_child_exit(int signal_number) {
    (void) signal_number;

    pid_t pid = (pid_t) child_pid;
    if (pid > 0) {
        signal_child_group(pid, SIGKILL);
    }
}

static void forward_signal(int signal_number) {
    termination_requested = 1;
    pid_t pid = (pid_t) child_pid;
    if (pid > 0) {
        signal_child_group(pid, signal_number);
        arm_termination_deadline();
    } else {
        pending_signal = signal_number;
    }
}

static void install_signal_handlers(void) {
    struct sigaction action = {0};
    sigemptyset(&action.sa_mask);
    action.sa_handler = forward_signal;

    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGQUIT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    action.sa_handler = force_child_exit;
    sigaction(SIGALRM, &action, NULL);
}

static int run_helper_process(int argc, const char *argv[]) {
    if (argc != 4 || strcmp(argv[1], "--run-helper") != 0) {
        return 64;
    }
    if (setpgid(0, 0) == -1) {
        fprintf(stderr, "Funk Android launcher could not create its process group: %s\n",
                strerror(errno));
        return 69;
    }
    execl(argv[2], argv[2], argv[3], (char *) NULL);
    fprintf(stderr, "Funk Android launcher could not start %s: %s\n",
            argv[2], strerror(errno));
    return 69;
}

@interface FunkAndroidLauncherDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) NSTask *task;

@end


@implementation FunkAndroidLauncherDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void) notification;

    NSString *modePath = [[NSBundle mainBundle] pathForResource:@"launcher-mode"
                                                         ofType:nil];
    NSError *readError = nil;
    NSString *mode = [NSString stringWithContentsOfFile:modePath ?: @""
                                                encoding:NSUTF8StringEncoding
                                                   error:&readError];
    mode = [mode stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSSet<NSString *> *validModes = [NSSet setWithArray:@[
        @"audio", @"no-audio", @"flex-audio", @"flex-no-audio"
    ]];
    if (readError || ![validModes containsObject:mode]) {
        NSLog(@"Funk Android launcher has an invalid mode resource: %@",
              readError.localizedDescription ?: mode);
        exit(64);
    }

    NSString *helper = [[NSBundle mainBundle] pathForResource:@"android-screen-copy"
                                                       ofType:nil];
    if (helper == nil ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
        NSLog(@"Funk Android launcher has no executable Screen Copy helper");
        exit(66);
    }

    NSString *jobLauncher = [[NSBundle mainBundle] pathForResource:@"FunkAndroidJob"
                                                            ofType:nil];
    if (jobLauncher == nil ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:jobLauncher]) {
        NSLog(@"Funk Android launcher has no executable job trampoline");
        exit(66);
    }

    NSTask *task = [[NSTask alloc] init];
    // Running the bundle's CFBundleExecutable again can make RunningBoard
    // classify the trampoline as another application instance. The identical
    // non-principal resource binary is an ordinary supervised child instead.
    task.executableURL = [NSURL fileURLWithPath:jobLauncher];
    task.arguments = @[@"--run-helper", helper, mode];
    self.task = task;

    __weak FunkAndroidLauncherDelegate *weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        if (termination_requested) {
            // The group leader can exit before a stubborn preflight descendant.
            // Remove anything still in the launcher's private process group.
            kill(-finishedTask.processIdentifier, SIGKILL);
        }
        alarm(0);
        termination_deadline_armed = 0;
        termination_requested = 0;
        child_pid = 0;
        int status = finishedTask.terminationStatus;
        if (finishedTask.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
            status = 128 + status;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.task = nil;
            exit(status);
        });
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        NSLog(@"Funk Android launcher could not start %@: %@",
              helper, launchError.localizedDescription);
        self.task = nil;
        exit(69);
    }

    child_pid = task.processIdentifier;
    int signal_number = (int) pending_signal;
    if (signal_number != 0) {
        pending_signal = 0;
        signal_child_group(task.processIdentifier, signal_number);
        arm_termination_deadline();
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void) sender;

    NSTask *task = self.task;
    if (task.running) {
        termination_requested = 1;
        signal_child_group(task.processIdentifier, SIGTERM);
        arm_termination_deadline();
        return NSTerminateLater;
    }
    return NSTerminateNow;
}

@end


int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--run-helper") == 0) {
        return run_helper_process(argc, argv);
    }
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        install_signal_handlers();
        FunkAndroidLauncherDelegate *delegate =
            [[FunkAndroidLauncherDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
