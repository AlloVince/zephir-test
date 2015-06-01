/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process;

use Symfony\Component\Process\Exception\InvalidArgumentException;
use Symfony\Component\Process\Exception\LogicException;
use Symfony\Component\Process\Exception\ProcessFailedException;
use Symfony\Component\Process\Exception\ProcessTimedOutException;
use Symfony\Component\Process\Exception\RuntimeException;
use Symfony\Component\Process\Pipes\PipesInterface;
use Symfony\Component\Process\Pipes\UnixPipes;
use Symfony\Component\Process\Pipes\WindowsPipes;
/**
 * Process is a thin wrapper around proc_* functions to easily
 * start independent PHP processes.
 *
 * @author Fabien Potencier <fabien@symfony.com>
 * @author Romain Neutron <imprec@gmail.com>
 *
 * @api
 */
class Process
{
    const ERR = "err";
    const OUT = "out";
    const STATUS_READY = "ready";
    const STATUS_STARTED = "started";
    const STATUS_TERMINATED = "terminated";
    const STDIN = 0;
    const STDOUT = 1;
    const STDERR = 2;
    // Timeout Precision in seconds.
    const TIMEOUT_PRECISION = 0.2;
    protected callback;
    protected commandline;
    protected cwd;
    protected env;
    protected input;
    protected starttime;
    protected lastOutputTime;
    protected timeout;
    protected idleTimeout;
    protected options;
    protected exitcode;
    protected fallbackExitcode;
    protected processInformation;
    protected outputDisabled = false;
    protected stdout;
    protected stderr;
    protected enhanceWindowsCompatibility = true;
    protected enhanceSigchildCompatibility;
    protected process;
    protected status = self::STATUS_READY;
    protected incrementalOutputOffset = 0;
    protected incrementalErrorOutputOffset = 0;
    protected tty;
    protected pty;
    protected useFileHandles = false;
    /** @var PipesInterface */
    protected processPipes;
    protected latestSignal;
    protected static sigchild;
    /**
     * Exit codes translation table.
     *
     * User-defined errors must use exit codes in the 64-113 range.
     *
     * @var array
     */
    public exitCodes = [0 : "OK", 1 : "General error", 2 : "Misuse of shell builtins", 126 : "Invoked command cannot execute", 127 : "Command not found", 128 : "Invalid exit argument", 129 : "Hangup", 130 : "Interrupt", 131 : "Quit and dump core", 132 : "Illegal instruction", 133 : "Trace/breakpoint trap", 134 : "Process aborted", 135 : "Bus error: \"access to undefined portion of memory object\"", 136 : "Floating point exception: \"erroneous arithmetic operation\"", 137 : "Kill (terminate immediately)", 138 : "User-defined 1", 139 : "Segmentation violation", 140 : "User-defined 2", 141 : "Write to pipe with no one reading", 142 : "Signal raised by alarm", 143 : "Termination (request to terminate)", 145 : "Child process terminated, stopped (or continued*)", 146 : "Continue if stopped", 147 : "Stop executing temporarily", 148 : "Terminal stop signal", 149 : "Background process attempting to read from tty (\"in\")", 150 : "Background process attempting to write to tty (\"out\")", 151 : "Urgent data available on socket", 152 : "CPU time limit exceeded", 153 : "File size limit exceeded", 154 : "Signal raised by timer counting virtual time: \"virtual timer expired\"", 155 : "Profiling timer expired", 157 : "Pollable event", 159 : "Bad syscall"];
    /**
     * Constructor.
     *
     * @param string         $commandline The command line to run
     * @param string|null    $cwd         The working directory or null to use the working dir of the current PHP process
     * @param array|null     $env         The environment variables or null to inherit
     * @param string|null    $input       The input
     * @param int|float|null $timeout     The timeout in seconds or null to disable
     * @param array          $options     An array of options for proc_open
     *
     * @throws RuntimeException When proc_open is not installed
     *
     * @api
     */
    public function __construct(string commandline, cwd = null, array env = null, input = null, timeout = 60, array options = []) -> void
    {
        
        if !function_exists("proc_open") {
            throw new RuntimeException("The Process class relies on proc_open, which is not available on your PHP installation.");
        }
        let this->commandline = commandline;
        let this->cwd = cwd;
        // on Windows, if the cwd changed via chdir(), proc_open defaults to the dir where PHP was started
        // on Gnu/Linux, PHP builds with --enable-maintainer-zts are also affected
        // @see : https://bugs.php.net/bug.php?id=51800
        // @see : https://bugs.php.net/bug.php?id=50524
        
        if this->cwd === null && (defined("ZEND_THREAD_SAFE") || DIRECTORY_SEPARATOR === "\\") {
            let this->cwd =  getcwd();
        }
        
        if env !== null {
            this->setEnv(env);
        }
        let this->input = input;
        this->setTimeout(timeout);
        let this->useFileHandles =  "\\" === DIRECTORY_SEPARATOR;
        let this->pty =  false;
        let this->enhanceWindowsCompatibility =  true;
        let this->enhanceSigchildCompatibility =  "\\" !== DIRECTORY_SEPARATOR && this->isSigchildEnabled();
        let this->options =  array_replace(["suppress_errors" : true, "binary_pipes" : true], options);
    }
    
    public function __destruct() -> void
    {
        // stop() will check if we have a process running.
        this->stop();
    }
    
    public function __clone() -> void
    {
        this->resetProcessData();
    }
    
    /**
     * Runs the process.
     *
     * The callback receives the type of output (out or err) and
     * some bytes from the output in real-time. It allows to have feedback
     * from the independent process during execution.
     *
     * The STDOUT and STDERR are also available after the process is finished
     * via the getOutput() and getErrorOutput() methods.
     *
     * @param callable|null $callback A PHP callback to run whenever there is some
     *                                output available on STDOUT or STDERR
     *
     * @return int The exit status code
     *
     * @throws RuntimeException When process can't be launched
     * @throws RuntimeException When process stopped after receiving signal
     * @throws LogicException   In case a callback is provided and output has been disabled
     *
     * @api
     */
    public function run(callback = null) -> int
    {
        this->start(callback);
        
        return this->wait();
    }
    
    /**
     * Runs the process.
     *
     * This is identical to run() except that an exception is thrown if the process
     * exits with a non-zero exit code.
     *
     * @param callable|null $callback
     *
     * @return self
     *
     * @throws RuntimeException       if PHP was compiled with --enable-sigchild and the enhanced sigchild compatibility mode is not enabled
     * @throws ProcessFailedException if the process didn't terminate successfully
     */
    public function mustRun(callback = null)
    {
        
        if this->isSigchildEnabled() && !this->enhanceSigchildCompatibility {
            throw new RuntimeException("This PHP has been compiled with --enable-sigchild. You must use setEnhanceSigchildCompatibility() to use this method.");
        }
        
        if this->run(callback) !== 0 {
            throw new ProcessFailedException(this);
        }
        
        return this;
    }
    
    /**
     * Starts the process and returns after writing the input to STDIN.
     *
     * This method blocks until all STDIN data is sent to the process then it
     * returns while the process runs in the background.
     *
     * The termination of the process can be awaited with wait().
     *
     * The callback receives the type of output (out or err) and some bytes from
     * the output in real-time while writing the standard input to the process.
     * It allows to have feedback from the independent process during execution.
     * If there is no callback passed, the wait() method can be called
     * with true as a second parameter then the callback will get all data occurred
     * in (and since) the start call.
     *
     * @param callable|null $callback A PHP callback to run whenever there is some
     *                                output available on STDOUT or STDERR
     *
     * @throws RuntimeException When process can't be launched
     * @throws RuntimeException When process is already running
     * @throws LogicException   In case a callback is provided and output has been disabled
     */
    public function start(callback = null)
    {
        var descriptors, commandline, offset, filename;
    
        
        if this->isRunning() {
            throw new RuntimeException("Process is already running");
        }
        
        if this->outputDisabled && callback !== null {
            throw new LogicException("Output has been disabled, enable it to allow the use of a callback.");
        }
        this->resetProcessData();
        let this->starttime = microtime(true);
        let this->lastOutputTime = microtime(true);
        ;
        let this->callback =  this->buildCallback(callback);
        let descriptors =  this->getDescriptors();
        let commandline =  this->commandline;
        
        if DIRECTORY_SEPARATOR === "\\" && this->enhanceWindowsCompatibility {
            let commandline =  "cmd /V:ON /E:ON /C \"(" . commandline . ")";
            for offset, filename in this->processPipes->getFiles() {
                let commandline .= " " . offset . ">" . ProcessUtils::escapeArgument(filename);
            }
            let commandline .= "\"";
            
            if !isset this->options["bypass_shell"] {
                let this->options["bypass_shell"] = true;
            }
        }
        let this->process =  proc_open(commandline, descriptors, this->processPipes->pipes, this->cwd, this->env, this->options);
        
        if !is_resource(this->process) {
            throw new RuntimeException("Unable to launch a new process.");
        }
        let this->status =  self::STATUS_STARTED;
        
        if this->tty {
            
            return;
        }
        this->updateStatus(false);
        this->checkTimeout();
    }
    
    /**
     * Restarts the process.
     *
     * Be warned that the process is cloned before being started.
     *
     * @param callable|null $callback A PHP callback to run whenever there is some
     *                                output available on STDOUT or STDERR
     *
     * @return Process The new process
     *
     * @throws RuntimeException When process can't be launched
     * @throws RuntimeException When process is already running
     *
     * @see start()
     */
    public function restart(callback = null)
    {
        var process;
    
        
        if this->isRunning() {
            throw new RuntimeException("Process is already running");
        }
        let process =  clone this;
        process->start(callback);
        
        return process;
    }
    
    /**
     * Waits for the process to terminate.
     *
     * The callback receives the type of output (out or err) and some bytes
     * from the output in real-time while writing the standard input to the process.
     * It allows to have feedback from the independent process during execution.
     *
     * @param callable|null $callback A valid PHP callback
     *
     * @return int The exitcode of the process
     *
     * @throws RuntimeException When process timed out
     * @throws RuntimeException When process stopped after receiving signal
     * @throws LogicException   When process is not yet started
     */
    public function wait(callback = null) -> int
    {
        var running, close;
    
        this->requireProcessIsStarted(__FUNCTION__);
        this->updateStatus(false);
        
        if callback !== null {
            let this->callback =  this->buildCallback(callback);
        }
        do {
            this->checkTimeout();
            
            let running =  DIRECTORY_SEPARATOR === "\\" ? this->isRunning() : this->processPipes->areOpen();
            let close =  "\\" !== DIRECTORY_SEPARATOR || !running;
            this->readPipes(true, close);
        } while (running);
        
        while (this->isRunning()) {
            usleep(1000);
        
        }
        
        if this->processInformation["signaled"] && this->processInformation["termsig"] !== this->latestSignal {
            throw new RuntimeException(sprintf("The process has been signaled with signal \"%s\".", this->processInformation["termsig"]));
        }
        
        return this->exitcode;
    }
    
    /**
     * Returns the Pid (process identifier), if applicable.
     *
     * @return int|null The process id if running, null otherwise
     *
     * @throws RuntimeException In case --enable-sigchild is activated
     */
    public function getPid()
    {
        
        if this->isSigchildEnabled() {
            throw new RuntimeException("This PHP has been compiled with --enable-sigchild. The process identifier can not be retrieved.");
        }
        this->updateStatus(false);
        
        return 
        this->isRunning() ? this->processInformation["pid"] : null;
    }
    
    /**
     * Sends a POSIX signal to the process.
     *
     * @param int $signal A valid POSIX signal (see http://www.php.net/manual/en/pcntl.constants.php)
     *
     * @return Process
     *
     * @throws LogicException   In case the process is not running
     * @throws RuntimeException In case --enable-sigchild is activated
     * @throws RuntimeException In case of failure
     */
    public function signal(int signal)
    {
        this->doSignal(signal, true);
        
        return this;
    }
    
    /**
     * Disables fetching output and error output from the underlying process.
     *
     * @return Process
     *
     * @throws RuntimeException In case the process is already running
     * @throws LogicException   if an idle timeout is set
     */
    public function disableOutput()
    {
        
        if this->isRunning() {
            throw new RuntimeException("Disabling output while the process is running is not possible.");
        }
        
        if this->idleTimeout !== null {
            throw new LogicException("Output can not be disabled while an idle timeout is set.");
        }
        let this->outputDisabled =  true;
        
        return this;
    }
    
    /**
     * Enables fetching output and error output from the underlying process.
     *
     * @return Process
     *
     * @throws RuntimeException In case the process is already running
     */
    public function enableOutput()
    {
        
        if this->isRunning() {
            throw new RuntimeException("Enabling output while the process is running is not possible.");
        }
        let this->outputDisabled =  false;
        
        return this;
    }
    
    /**
     * Returns true in case the output is disabled, false otherwise.
     *
     * @return bool
     */
    public function isOutputDisabled() -> bool
    {
        
        return this->outputDisabled;
    }
    
    /**
     * Returns the current output of the process (STDOUT).
     *
     * @return string The process output
     *
     * @throws LogicException in case the output has been disabled
     * @throws LogicException In case the process is not started
     *
     * @api
     */
    public function getOutput() -> string
    {
        
        if this->outputDisabled {
            throw new LogicException("Output has been disabled.");
        }
        this->requireProcessIsStarted(__FUNCTION__);
        this->readPipes(false, 
        "\\" === DIRECTORY_SEPARATOR ? !this->processInformation["running"] : true);
        
        return this->stdout;
    }
    
    /**
     * Returns the output incrementally.
     *
     * In comparison with the getOutput method which always return the whole
     * output, this one returns the new output since the last call.
     *
     * @throws LogicException in case the output has been disabled
     * @throws LogicException In case the process is not started
     *
     * @return string The process output since the last call
     */
    public function getIncrementalOutput() -> string
    {
        var data, latest;
    
        this->requireProcessIsStarted(__FUNCTION__);
        let data =  this->getOutput();
        let latest =  substr(data, this->incrementalOutputOffset);
        
        if latest === false {
            
            return "";
        }
        let this->incrementalOutputOffset =  strlen(data);
        
        return latest;
    }
    
    /**
     * Clears the process output.
     *
     * @return Process
     */
    public function clearOutput()
    {
        let this->stdout = "";
        let this->incrementalOutputOffset = 0;
        
        return this;
    }
    
    /**
     * Returns the current error output of the process (STDERR).
     *
     * @return string The process error output
     *
     * @throws LogicException in case the output has been disabled
     * @throws LogicException In case the process is not started
     *
     * @api
     */
    public function getErrorOutput() -> string
    {
        
        if this->outputDisabled {
            throw new LogicException("Output has been disabled.");
        }
        this->requireProcessIsStarted(__FUNCTION__);
        this->readPipes(false, 
        "\\" === DIRECTORY_SEPARATOR ? !this->processInformation["running"] : true);
        
        return this->stderr;
    }
    
    /**
     * Returns the errorOutput incrementally.
     *
     * In comparison with the getErrorOutput method which always return the
     * whole error output, this one returns the new error output since the last
     * call.
     *
     * @throws LogicException in case the output has been disabled
     * @throws LogicException In case the process is not started
     *
     * @return string The process error output since the last call
     */
    public function getIncrementalErrorOutput() -> string
    {
        var data, latest;
    
        this->requireProcessIsStarted(__FUNCTION__);
        let data =  this->getErrorOutput();
        let latest =  substr(data, this->incrementalErrorOutputOffset);
        
        if latest === false {
            
            return "";
        }
        let this->incrementalErrorOutputOffset =  strlen(data);
        
        return latest;
    }
    
    /**
     * Clears the process output.
     *
     * @return Process
     */
    public function clearErrorOutput()
    {
        let this->stderr = "";
        let this->incrementalErrorOutputOffset = 0;
        
        return this;
    }
    
    /**
     * Returns the exit code returned by the process.
     *
     * @return null|int The exit status code, null if the Process is not terminated
     *
     * @throws RuntimeException In case --enable-sigchild is activated and the sigchild compatibility mode is disabled
     *
     * @api
     */
    public function getExitCode()
    {
        
        if this->isSigchildEnabled() && !this->enhanceSigchildCompatibility {
            throw new RuntimeException("This PHP has been compiled with --enable-sigchild. You must use setEnhanceSigchildCompatibility() to use this method.");
        }
        this->updateStatus(false);
        
        return this->exitcode;
    }
    
    /**
     * Returns a string representation for the exit code returned by the process.
     *
     * This method relies on the Unix exit code status standardization
     * and might not be relevant for other operating systems.
     *
     * @return null|string A string representation for the exit status code, null if the Process is not terminated.
     *
     * @throws RuntimeException In case --enable-sigchild is activated and the sigchild compatibility mode is disabled
     *
     * @see http://tldp.org/LDP/abs/html/exitcodes.html
     * @see http://en.wikipedia.org/wiki/Unix_signal
     */
    public function getExitCodeText()
    {
        var exitcode;
    
        let exitcode =  this->getExitCode();
        if exitcode === null {
            
            return;
        }
        
        return 
        isset this->exitCodes[exitcode] ? this->exitCodes[exitcode] : "Unknown error";
    }
    
    /**
     * Checks if the process ended successfully.
     *
     * @return bool true if the process ended successfully, false otherwise
     *
     * @api
     */
    public function isSuccessful() -> bool
    {
        
        return this->getExitCode() === 0;
    }
    
    /**
     * Returns true if the child process has been terminated by an uncaught signal.
     *
     * It always returns false on Windows.
     *
     * @return bool
     *
     * @throws RuntimeException In case --enable-sigchild is activated
     * @throws LogicException   In case the process is not terminated
     *
     * @api
     */
    public function hasBeenSignaled() -> bool
    {
        this->requireProcessIsTerminated(__FUNCTION__);
        
        if this->isSigchildEnabled() {
            throw new RuntimeException("This PHP has been compiled with --enable-sigchild. Term signal can not be retrieved.");
        }
        this->updateStatus(false);
        
        return this->processInformation["signaled"];
    }
    
    /**
     * Returns the number of the signal that caused the child process to terminate its execution.
     *
     * It is only meaningful if hasBeenSignaled() returns true.
     *
     * @return int
     *
     * @throws RuntimeException In case --enable-sigchild is activated
     * @throws LogicException   In case the process is not terminated
     *
     * @api
     */
    public function getTermSignal() -> int
    {
        this->requireProcessIsTerminated(__FUNCTION__);
        
        if this->isSigchildEnabled() {
            throw new RuntimeException("This PHP has been compiled with --enable-sigchild. Term signal can not be retrieved.");
        }
        this->updateStatus(false);
        
        return this->processInformation["termsig"];
    }
    
    /**
     * Returns true if the child process has been stopped by a signal.
     *
     * It always returns false on Windows.
     *
     * @return bool
     *
     * @throws LogicException In case the process is not terminated
     *
     * @api
     */
    public function hasBeenStopped() -> bool
    {
        this->requireProcessIsTerminated(__FUNCTION__);
        this->updateStatus(false);
        
        return this->processInformation["stopped"];
    }
    
    /**
     * Returns the number of the signal that caused the child process to stop its execution.
     *
     * It is only meaningful if hasBeenStopped() returns true.
     *
     * @return int
     *
     * @throws LogicException In case the process is not terminated
     *
     * @api
     */
    public function getStopSignal() -> int
    {
        this->requireProcessIsTerminated(__FUNCTION__);
        this->updateStatus(false);
        
        return this->processInformation["stopsig"];
    }
    
    /**
     * Checks if the process is currently running.
     *
     * @return bool true if the process is currently running, false otherwise
     */
    public function isRunning() -> bool
    {
        
        if self::STATUS_STARTED !== this->status {
            
            return false;
        }
        this->updateStatus(false);
        
        return this->processInformation["running"];
    }
    
    /**
     * Checks if the process has been started with no regard to the current state.
     *
     * @return bool true if status is ready, false otherwise
     */
    public function isStarted() -> bool
    {
        
        return this->status != self::STATUS_READY;
    }
    
    /**
     * Checks if the process is terminated.
     *
     * @return bool true if process is terminated, false otherwise
     */
    public function isTerminated() -> bool
    {
        this->updateStatus(false);
        
        return this->status == self::STATUS_TERMINATED;
    }
    
    /**
     * Gets the process status.
     *
     * The status is one of: ready, started, terminated.
     *
     * @return string The current process status
     */
    public function getStatus() -> string
    {
        this->updateStatus(false);
        
        return this->status;
    }
    
    /**
     * Stops the process.
     *
     * @param int|float $timeout The timeout in seconds
     * @param int       $signal  A POSIX signal to send in case the process has not stop at timeout, default is SIGKILL
     *
     * @return int The exit-code of the process
     *
     * @throws RuntimeException if the process got signaled
     */
    public function stop(timeout = 10, int signal = null) -> int
    {
        var timeoutMicro;
    
        let timeoutMicro =  microtime(true) + timeout;
        
        if this->isRunning() {
            
            if DIRECTORY_SEPARATOR === "\\" && !this->isSigchildEnabled() {
                exec(sprintf("taskkill /F /T /PID %d 2>&1", this->getPid()), output, exitCode);
                
                if exitCode > 0 {
                    throw new RuntimeException("Unable to kill the process");
                }
            }
            // given `SIGTERM` may not be defined and that `proc_terminate` uses the constant value and not the constant itself, we use the same here
            this->doSignal(15, false);
            do {
                usleep(1000);
            } while (this->isRunning() && microtime(true) < timeoutMicro);
            
            if this->isRunning() && !this->isSigchildEnabled() {
                
                if signal !== null || defined("SIGKILL") {
                    // avoid exception here :
                    // process is supposed to be running, but it might have stop
                    // just after this line.
                    // in any case, let's silently discard the error, we can not do anything
                    this->doSignal(
                    signal ?: SIGKILL, false);
                }
            }
        }
        this->updateStatus(false);
        
        if this->processInformation["running"] {
            this->close();
        }
        
        return this->exitcode;
    }
    
    /**
     * Adds a line to the STDOUT stream.
     *
     * @param string $line The line to append
     */
    public function addOutput(string line) -> void
    {
        let this->lastOutputTime =  microtime(true);
        let this->stdout .= line;
    }
    
    /**
     * Adds a line to the STDERR stream.
     *
     * @param string $line The line to append
     */
    public function addErrorOutput(string line) -> void
    {
        let this->lastOutputTime =  microtime(true);
        let this->stderr .= line;
    }
    
    /**
     * Gets the command line to be executed.
     *
     * @return string The command to execute
     */
    public function getCommandLine() -> string
    {
        
        return this->commandline;
    }
    
    /**
     * Sets the command line to be executed.
     *
     * @param string $commandline The command to execute
     *
     * @return self The current Process instance
     */
    public function setCommandLine(string commandline)
    {
        let this->commandline = commandline;
        
        return this;
    }
    
    /**
     * Gets the process timeout (max. runtime).
     *
     * @return float|null The timeout in seconds or null if it's disabled
     */
    public function getTimeout()
    {
        
        return this->timeout;
    }
    
    /**
     * Gets the process idle timeout (max. time since last output).
     *
     * @return float|null The timeout in seconds or null if it's disabled
     */
    public function getIdleTimeout()
    {
        
        return this->idleTimeout;
    }
    
    /**
     * Sets the process timeout (max. runtime).
     *
     * To disable the timeout, set this value to null.
     *
     * @param int|float|null $timeout The timeout in seconds
     *
     * @return self The current Process instance
     *
     * @throws InvalidArgumentException if the timeout is negative
     */
    public function setTimeout(timeout)
    {
        let this->timeout =  this->validateTimeout(timeout);
        
        return this;
    }
    
    /**
     * Sets the process idle timeout (max. time since last output).
     *
     * To disable the timeout, set this value to null.
     *
     * @param int|float|null $timeout The timeout in seconds
     *
     * @return self The current Process instance.
     *
     * @throws LogicException           if the output is disabled
     * @throws InvalidArgumentException if the timeout is negative
     */
    public function setIdleTimeout(timeout)
    {
        
        if timeout !== null && this->outputDisabled {
            throw new LogicException("Idle timeout can not be set while the output is disabled.");
        }
        let this->idleTimeout =  this->validateTimeout(timeout);
        
        return this;
    }
    
    /**
     * Enables or disables the TTY mode.
     *
     * @param bool $tty True to enabled and false to disable
     *
     * @return self The current Process instance
     *
     * @throws RuntimeException In case the TTY mode is not supported
     */
    public function setTty(bool tty)
    {
        
        if DIRECTORY_SEPARATOR === "\\" && tty {
            throw new RuntimeException("TTY mode is not supported on Windows platform.");
        }
        
        if tty && (!file_exists("/dev/tty") || !is_readable("/dev/tty")) {
            throw new RuntimeException("TTY mode requires /dev/tty to be readable.");
        }
        let this->tty =  (bool) tty;
        
        return this;
    }
    
    /**
     * Checks if the TTY mode is enabled.
     *
     * @return bool true if the TTY mode is enabled, false otherwise
     */
    public function isTty() -> bool
    {
        
        return this->tty;
    }
    
    /**
     * Sets PTY mode.
     *
     * @param bool $bool
     *
     * @return self
     */
    public function setPty(bool booll)
    {
        let this->pty =  (bool) booll;
        
        return this;
    }
    
    /**
     * Returns PTY state.
     *
     * @return bool
     */
    public function isPty() -> bool
    {
        
        return this->pty;
    }
    
    /**
     * Gets the working directory.
     *
     * @return string|null The current working directory or null on failure
     */
    public function getWorkingDirectory()
    {
        
        if this->cwd === null {
            // getcwd() will return false if any one of the parent directories does not have
            // the readable or search mode set, even if the current directory does
            
            return 
            getcwd() ?: null;
        }
        
        return this->cwd;
    }
    
    /**
     * Sets the current working directory.
     *
     * @param string $cwd The new working directory
     *
     * @return self The current Process instance
     */
    public function setWorkingDirectory(string cwd)
    {
        let this->cwd = cwd;
        
        return this;
    }
    
    /**
     * Gets the environment variables.
     *
     * @return array The current environment variables
     */
    public function getEnv() -> array
    {
        
        return this->env;
    }
    
    /**
     * Sets the environment variables.
     *
     * An environment variable value should be a string.
     * If it is an array, the variable is ignored.
     *
     * That happens in PHP when 'argv' is registered into
     * the $_ENV array for instance.
     *
     * @param array $env The new environment variables
     *
     * @return self The current Process instance
     */
    public function setEnv(array env)
    {
        var key, value;
    
        // Process can not handle env values that are arrays
        let env =  array_filter(env, new ProcesssetEnvClosureOne());
        
        let this->env =  [];
        for key, value in env {
            let this->env[(string) key] = (string) value;
        }
        
        return this;
    }
    
    /**
     * Gets the Process input.
     *
     * @return null|string The Process input
     */
    public function getInput()
    {
        
        return this->input;
    }
    
    /**
     * Sets the input.
     *
     * This content will be passed to the underlying process standard input.
     *
     * @param mixed $input The content
     *
     * @return self The current Process instance
     *
     * @throws LogicException In case the process is running
     */
    public function setInput(input)
    {
        
        if this->isRunning() {
            throw new LogicException("Input can not be set while the process is running.");
        }
        let this->input =  ProcessUtils::validateInput(sprintf("%s::%s", __CLASS__, __FUNCTION__), input);
        
        return this;
    }
    
    /**
     * Gets the options for proc_open.
     *
     * @return array The current options
     */
    public function getOptions() -> array
    {
        
        return this->options;
    }
    
    /**
     * Sets the options for proc_open.
     *
     * @param array $options The new options
     *
     * @return self The current Process instance
     */
    public function setOptions(array options)
    {
        let this->options = options;
        
        return this;
    }
    
    /**
     * Gets whether or not Windows compatibility is enabled.
     *
     * This is true by default.
     *
     * @return bool
     */
    public function getEnhanceWindowsCompatibility() -> bool
    {
        
        return this->enhanceWindowsCompatibility;
    }
    
    /**
     * Sets whether or not Windows compatibility is enabled.
     *
     * @param bool $enhance
     *
     * @return self The current Process instance
     */
    public function setEnhanceWindowsCompatibility(bool enhance)
    {
        let this->enhanceWindowsCompatibility =  (bool) enhance;
        
        return this;
    }
    
    /**
     * Returns whether sigchild compatibility mode is activated or not.
     *
     * @return bool
     */
    public function getEnhanceSigchildCompatibility() -> bool
    {
        
        return this->enhanceSigchildCompatibility;
    }
    
    /**
     * Activates sigchild compatibility mode.
     *
     * Sigchild compatibility mode is required to get the exit code and
     * determine the success of a process when PHP has been compiled with
     * the --enable-sigchild option
     *
     * @param bool $enhance
     *
     * @return self The current Process instance
     */
    public function setEnhanceSigchildCompatibility(bool enhance)
    {
        let this->enhanceSigchildCompatibility =  (bool) enhance;
        
        return this;
    }
    
    /**
     * Performs a check between the timeout definition and the time the process started.
     *
     * In case you run a background process (with the start method), you should
     * trigger this method regularly to ensure the process timeout
     *
     * @throws ProcessTimedOutException In case the timeout was reached
     */
    public function checkTimeout()
    {
        
        if this->status !== self::STATUS_STARTED {
            
            return;
        }
        
        if this->timeout !== null && this->timeout < microtime(true) - this->starttime {
            this->stop(0);
            throw new ProcessTimedOutException(this, ProcessTimedOutException::TYPE_GENERAL);
        }
        
        if this->idleTimeout !== null && this->idleTimeout < microtime(true) - this->lastOutputTime {
            this->stop(0);
            throw new ProcessTimedOutException(this, ProcessTimedOutException::TYPE_IDLE);
        }
    }
    
    /**
     * Returns whether PTY is supported on the current operating system.
     *
     * @return bool
     */
    public static function isPtySupported() -> bool
    {
        var result, proc;
    
        static $result;
        
        if result !== null {
            
            return result;
        }
        
        if DIRECTORY_SEPARATOR === "\\" {
            let result =  false;
            return result;
        }
        let proc =  @proc_open("echo 1", [["pty"], ["pty"], ["pty"]], pipes);
        
        if is_resource(proc) {
            proc_close(proc);
            let result =  true;
            return result;
        }
        let result =  false;
        return result;
    }
    
    /**
     * Creates the descriptors needed by the proc_open.
     *
     * @return array
     */
    protected function getDescriptors() -> array
    {
        var processPipes, descriptors, tmpArraya5442979427271f9ba5c4a0bf5245e79, tmpArray4eed438b1bfbb8a7b642fa2b72c96cc6, commandline;
    
        
        if DIRECTORY_SEPARATOR === "\\" {
            let this->processPipes =  WindowsPipes::create(this, this->input);
        } else {
            let this->processPipes =  UnixPipes::create(this, this->input);
        }
        let descriptors =  this->processPipes->getDescriptors(this->outputDisabled);
        
        if !this->useFileHandles && this->enhanceSigchildCompatibility && this->isSigchildEnabled() {
            // last exit code is output on the fourth pipe and caught to work around --enable-sigchild
            let descriptors =  array_merge(descriptors, [["pipe", "w"]]);
            let this->commandline =  "(" . this->commandline . ") 3>/dev/null; code=$?; echo $code >&3; exit $code";
        }
        
        return descriptors;
    }
    
    /**
     * Builds up the callback used by wait().
     *
     * The callbacks adds all occurred output to the specific buffer and calls
     * the user callback (if present) with the received output.
     *
     * @param callable|null $callback The user defined PHP callback
     *
     * @return callable A PHP callable
     */
    protected function buildCallback(callback)
    {
        var out;
    
        let out =  self::OUT;
        let callback =  new ProcessbuildCallbackClosureOne(callback, out);
        
        return callback;
    }
    
    /**
     * Updates the status of the process, reads pipes.
     *
     * @param bool $blocking Whether to use a blocking read call.
     */
    protected function updateStatus(bool blocking)
    {
        
        if self::STATUS_STARTED !== this->status {
            
            return;
        }
        let this->processInformation =  proc_get_status(this->process);
        this->captureExitCode();
        this->readPipes(blocking, 
        "\\" === DIRECTORY_SEPARATOR ? !this->processInformation["running"] : true);
        
        if !this->processInformation["running"] {
            this->close();
        }
    }
    
    /**
     * Returns whether PHP has been compiled with the '--enable-sigchild' option or not.
     *
     * @return bool
     */
    protected function isSigchildEnabled() -> bool
    {
        var sigchild;
    
        
        if self::$sigchild !== null {
            
            return self::$sigchild;
        }
        
        if !function_exists("phpinfo") {
            let self::$sigchild =  false;
            return self::$sigchild;
        }
        ob_start();
        phpinfo(INFO_GENERAL);
        let self::$sigchild =  false;
        return self::$sigchild;
    }
    
    /**
     * Validates and returns the filtered timeout.
     *
     * @param int|float|null $timeout
     *
     * @return float|null
     *
     * @throws InvalidArgumentException if the given timeout is a negative number
     */
    protected function validateTimeout(timeout)
    {
        let timeout =  (double) timeout;
        
        if timeout === 0 {
            let timeout =  null;
        } else { 
        
        if timeout < 0 {
            throw new InvalidArgumentException("The timeout value must be a valid positive integer or float number.");
        }
        }
        
        return timeout;
    }
    
    /**
     * Reads pipes, executes callback.
     *
     * @param bool $blocking Whether to use blocking calls or not.
     * @param bool $close    Whether to close file handles or not.
     */
    protected function readPipes(bool blocking, bool close) -> void
    {
        var result, callback, type, data, fallbackExitcode;
    
        let result =  this->processPipes->readAndWrite(blocking, close);
        let callback =  this->callback;
        for type, data in result {
            
            if type == 3 {
                let this->fallbackExitcode =  (int) data;
            } else {
                {callback}(
                type === self::STDOUT ? self::OUT : self::ERR, data);
            }
        }
    }
    
    /**
     * Captures the exitcode if mentioned in the process information.
     */
    protected function captureExitCode() -> void
    {
        var exitcode;
    
        
        if isset this->processInformation["exitcode"] && -1 != this->processInformation["exitcode"] {
            let this->exitcode = this->processInformation["exitcode"];
        }
    }
    
    /**
     * Closes process resource, closes file handles, sets the exitcode.
     *
     * @return int The exitcode
     */
    protected function close() -> int
    {
        var exitcode;
    
        this->processPipes->close();
        
        if is_resource(this->process) {
            let exitcode =  proc_close(this->process);
        } else {
            let exitcode =  -1;
        }
        
        let this->exitcode =  -1 !== exitcode ? exitcode : (
        this->exitcode !== null ? this->exitcode : -1);
        let this->status =  self::STATUS_TERMINATED;
        
        if -1 === this->exitcode && this->fallbackExitcode !== null {
            let this->exitcode =  this->fallbackExitcode;
        } else { 
        
        if -1 === this->exitcode && this->processInformation["signaled"] && this->processInformation["termsig"] < 0 {
            // if process has been signaled, no exitcode but a valid termsig, apply Unix convention
            let this->exitcode =  128 + this->processInformation["termsig"];
        }
        }
        
        return this->exitcode;
    }
    
    /**
     * Resets data related to the latest run of the process.
     */
    protected function resetProcessData() -> void
    {
        let this->starttime =  null;
        let this->callback =  null;
        let this->exitcode =  null;
        let this->fallbackExitcode =  null;
        let this->processInformation =  null;
        let this->stdout =  null;
        let this->stderr =  null;
        let this->process =  null;
        let this->latestSignal =  null;
        let this->status =  self::STATUS_READY;
        let this->incrementalOutputOffset = 0;
        let this->incrementalErrorOutputOffset = 0;
    }
    
    /**
     * Sends a POSIX signal to the process.
     *
     * @param int  $signal         A valid POSIX signal (see http://www.php.net/manual/en/pcntl.constants.php)
     * @param bool $throwException Whether to throw exception in case signal failed
     *
     * @return bool True if the signal was sent successfully, false otherwise
     *
     * @throws LogicException   In case the process is not running
     * @throws RuntimeException In case --enable-sigchild is activated
     * @throws RuntimeException In case of failure
     */
    protected function doSignal(int signal, bool throwException) -> bool
    {
        
        if !this->isRunning() {
            
            if throwException {
                throw new LogicException("Can not send signal on a non running process.");
            }
            
            return false;
        }
        
        if this->isSigchildEnabled() {
            
            if throwException {
                throw new RuntimeException("This PHP has been compiled with --enable-sigchild. The process can not be signaled.");
            }
            
            return false;
        }
        
        if @proc_terminate(this->process, signal) !== true {
            
            if throwException {
                throw new RuntimeException(sprintf("Error while sending signal `%s`.", signal));
            }
            
            return false;
        }
        let this->latestSignal = signal;
        
        return true;
    }
    
    /**
     * Ensures the process is running or terminated, throws a LogicException if the process has a not started.
     *
     * @param string $functionName The function name that was called.
     *
     * @throws LogicException If the process has not run.
     */
    protected function requireProcessIsStarted(string functionName) -> void
    {
        
        if !this->isStarted() {
            throw new LogicException(sprintf("Process must be started before calling %s.", functionName));
        }
    }
    
    /**
     * Ensures the process is terminated, throws a LogicException if the process has a status different than `terminated`.
     *
     * @param string $functionName The function name that was called.
     *
     * @throws LogicException If the process is not yet terminated.
     */
    protected function requireProcessIsTerminated(string functionName) -> void
    {
        
        if !this->isTerminated() {
            throw new LogicException(sprintf("Process must be terminated before calling %s.", functionName));
        }
    }

}