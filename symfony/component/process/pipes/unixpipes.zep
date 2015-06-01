/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process\Pipes;

use Symfony\Component\Process\Process;
/**
 * UnixPipes implementation uses unix pipes as handles.
 *
 * @author Romain Neutron <imprec@gmail.com>
 *
 * @internal
 */
class UnixPipes extends AbstractPipes
{
    /** @var bool */
    protected ttyMode;
    /** @var bool */
    protected ptyMode;
    /** @var bool */
    protected disableOutput;
    public function __construct(ttyMode, ptyMode, input, disableOutput) -> void
    {
        var inputBuffer;
    
        let this->ttyMode =  (bool) ttyMode;
        let this->ptyMode =  (bool) ptyMode;
        let this->disableOutput =  (bool) disableOutput;
        
        if is_resource(input) {
            let this->input = input;
        } else {
            let this->inputBuffer =  (string) input;
        }
    }
    
    public function __destruct() -> void
    {
        this->close();
    }
    
    /**
     * {@inheritdoc}
     */
    public function getDescriptors()
    {
        var nullstream, tmpArray899ff0c309729c09a7bd36de107c7b43, tmpArray1bffa74cc286de55045f9ac13deb22a5, tmpArraya3a54127aba01412e2b1d21c0ad940d5, tmpArray75d70e5cf0fdf0ee7b9636b21f6c0f98, tmpArray2cb4d900a16eacb894e6862eff350d69, tmpArray9e03534eb0958a7488336ecaf94e0880, tmpArray3260e2d5546bfa0d151268f162adb0cf, tmpArraye676e392f1375d6e4d411c210c7f5312, tmpArray14d059cabbf1d408826f348cd0e5716a, tmpArray6a1ab67198def08be2777ce99eebe1c2;
    
        
        if this->disableOutput {
            let nullstream =  fopen("/dev/null", "c");
            let tmpArray899ff0c309729c09a7bd36de107c7b43 = [["pipe", "r"], nullstream, nullstream];
            return tmpArray899ff0c309729c09a7bd36de107c7b43;
        }
        
        if this->ttyMode {
            let tmpArraya3a54127aba01412e2b1d21c0ad940d5 = [["file", "/dev/tty", "r"], ["file", "/dev/tty", "w"], ["file", "/dev/tty", "w"]];
            return tmpArraya3a54127aba01412e2b1d21c0ad940d5;
        }
        
        if this->ptyMode && Process::isPtySupported() {
            let tmpArray3260e2d5546bfa0d151268f162adb0cf = [["pty"], ["pty"], ["pty"]];
            return tmpArray3260e2d5546bfa0d151268f162adb0cf;
        }
        let tmpArrayf70cb3ce0f7cd61466fc5145585cc8c9 = [["pipe", "r"], ["pipe", "w"], ["pipe", "w"]];
        return tmpArrayf70cb3ce0f7cd61466fc5145585cc8c9;
    }
    
    /**
     * {@inheritdoc}
     */
    public function getFiles()
    {
        let tmpArray40cd750bba9870f18aada2478b24840a = [];
        return tmpArray40cd750bba9870f18aada2478b24840a;
    }
    
    /**
     * {@inheritdoc}
     */
    public function readAndWrite(blocking, close = false)
    {
        var tmpArray17c087a69b0b2eaf510b91c1949d9b31, tmpArray40cd750bba9870f18aada2478b24840a, read, r, tmpArrayf41241eec32fa6f64d73dc4d053d7929, w, e, n, pipes, pipe, type, found, data, dataread, input, written, inputBuffer;
    
        // only stdin is left open, job has been done !
        // we can now close it
        let tmpArray17c087a69b0b2eaf510b91c1949d9b31 = [0];
        if count(this->pipes) === 1 && array_keys(this->pipes) === tmpArray17c087a69b0b2eaf510b91c1949d9b31 {
            fclose(this->pipes[0]);
            unset(this->pipes[0]);
        
        }
        
        if empty(this->pipes) {
            let tmpArray40cd750bba9870f18aada2478b24840a = [];
            return tmpArray40cd750bba9870f18aada2478b24840a;
        }
        this->unblock();
        
        let read =  [];
        
        if this->input !== null {
            // if input is a resource, let's add it to stream_select argument to
            // fill a buffer
            let r =  array_merge(this->pipes, ["input" : this->input]);
        } else {
            let r =  this->pipes;
        }
        // discard read on stdin
        unset(r[0]);
        
        
        let w =  isset this->pipes[0] ? [this->pipes[0]] : null;
        let e =  null;
        // let's have a look if something changed in streams
        let n =  @stream_select(r, w, e, 0, 
        blocking ? Process::TIMEOUT_PRECISION * 1000000 : 0);
        if n === false {
            // if a system call has been interrupted, forget about it, let's try again
            // otherwise, an error occurred, let's reset pipes
            
            if !this->hasSystemCallBeenInterrupted() {
                
                let this->pipes =  [];
            }
            
            return read;
        }
        // nothing has changed
        
        if n === 0 {
            
            return read;
        }
        for pipe in r {
            // prior PHP 5.4 the array passed to stream_select is modified and
            // lose key association, we have to find back the key
            let found =  array_search(pipe, this->pipes);
            let type =  found !== false ? found : "input";
            let data = "";
            let dataread =  (string) fread(pipe, self::CHUNK_SIZE);
            while (dataread !== "") {
                let data .= dataread;
            let dataread =  (string) fread(pipe, self::CHUNK_SIZE);
            }
            
            if data !== "" {
                
                if type === "input" {
                    let this->inputBuffer .= data;
                } else {
                    let read[type] = data;
                }
            }
            
            if data === false || close === true && feof(pipe) && data === "" {
                
                if type === "input" {
                    // no more data to read on input resource
                    // use an empty buffer in the next reads
                    let this->input =  null;
                } else {
                    fclose(this->pipes[type]);
                    unset(this->pipes[type]);
                
                }
            }
        }
        
        if w !== null && count(w) < 0 {
            
            while (strlen(this->inputBuffer)) {
                let written =  fwrite(w[0], this->inputBuffer, 2 << 18);
                // write 512k
                
                if written > 0 {
                    let this->inputBuffer =  (string) substr(this->inputBuffer, written);
                } else {
                    break;
                }
            
            }
        }
        // no input to read on resource, buffer is empty and stdin still open
        
        if this->inputBuffer === "" && this->input === null && isset this->pipes[0] {
            fclose(this->pipes[0]);
            unset(this->pipes[0]);
        
        }
        
        return read;
    }
    
    /**
     * {@inheritdoc}
     */
    public function areOpen()
    {
        
        return (bool) this->pipes;
    }
    
    /**
     * Creates a new UnixPipes instance
     *
     * @param Process         $process
     * @param string|resource $input
     *
     * @return UnixPipes
     */
    public static function create(<\Symfony\Component\Process\Process> process, input)
    {
        
        return new static(process->isTty(), process->isPty(), input, process->isOutputDisabled());
    }

}