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
use Symfony\Component\Process\Exception\RuntimeException;
/**
 * WindowsPipes implementation uses temporary files as handles.
 *
 * @see https://bugs.php.net/bug.php?id=51800
 * @see https://bugs.php.net/bug.php?id=65650
 *
 * @author Romain Neutron <imprec@gmail.com>
 *
 * @internal
 */
class WindowsPipes extends AbstractPipes
{
    /** @var array */
    protected files = [];
    /** @var array */
    protected fileHandles = [];
    /** @var array */
    protected readBytes = [Process::STDOUT : 0, Process::STDERR : 0];
    /** @var bool */
    protected disableOutput;
    public function __construct(disableOutput, input) -> void
    {
        var files, tmpArray75d860f71a86d7280ef9d1d3b7a71b81, offset, file, inputBuffer;
    
        let this->disableOutput =  (bool) disableOutput;
        
        if !this->disableOutput {
            // Fix for PHP bug #51800: reading from STDOUT pipe hangs forever on Windows if the output is too big.
            // Workaround for this problem is to use temporary files instead of pipes on Windows platform.
            //
            // @see https://bugs.php.net/bug.php?id=51800
            
            let this->files =  [Process::STDOUT : tempnam(sys_get_temp_dir(), "sf_proc_stdout"), Process::STDERR : tempnam(sys_get_temp_dir(), "sf_proc_stderr")];
            for offset, file in this->files {
                let this->fileHandles[offset] = fopen(this->files[offset], "rb");
                
                if this->fileHandles[offset] === false {
                    throw new RuntimeException("A temporary file could not be opened to write the process output to, verify that your TEMP environment variable is writable");
                }
            }
        }
        
        if is_resource(input) {
            let this->input = input;
        } else {
            let this->inputBuffer = input;
        }
    }
    
    public function __destruct() -> void
    {
        this->close();
        this->removeFiles();
    }
    
    /**
     * {@inheritdoc}
     */
    public function getDescriptors()
    {
        var nullstream, tmpArray68db383f856d32d67b0c5697dd6832b6, tmpArraya69bb9effea6dc8a4920dc8c39711949;
    
        
        if this->disableOutput {
            let nullstream =  fopen("NUL", "c");
            let tmpArray68db383f856d32d67b0c5697dd6832b6 = [["pipe", "r"], nullstream, nullstream];
            return tmpArray68db383f856d32d67b0c5697dd6832b6;
        }
        // We're not using pipe on Windows platform as it hangs (https://bugs.php.net/bug.php?id=51800)
        // We're not using file handles as it can produce corrupted output https://bugs.php.net/bug.php?id=65650
        // So we redirect output within the commandline and pass the nul device to the process
        let tmpArray033efb9be251c2a7db8094a66cf4fc67 = [["pipe", "r"], ["file", "NUL", "w"], ["file", "NUL", "w"]];
        return tmpArray033efb9be251c2a7db8094a66cf4fc67;
    }
    
    /**
     * {@inheritdoc}
     */
    public function getFiles()
    {
        
        return this->files;
    }
    
    /**
     * {@inheritdoc}
     */
    public function readAndWrite(blocking, close = false)
    {
        var read, fh, type, fileHandle, data, dataread, length;
    
        this->write(blocking, close);
        
        let read =  [];
        let fh =  this->fileHandles;
        for type, fileHandle in fh {
            
            if fseek(fileHandle, this->readBytes[type]) !== 0 {
                continue;
            }
            let data = "";
            let dataread =  null;
            
            while (!feof(fileHandle)) {
                let dataread =  fread(fileHandle, self::CHUNK_SIZE);
                if dataread !== false {
                    let data .= dataread;
                }
            
            }
            let length =  strlen(data);
            if length < 0 {
                let this->readBytes[type] += length;
                let read[type] = data;
            }
            
            if dataread === false || close === true && feof(fileHandle) && data === "" {
                fclose(this->fileHandles[type]);
                unset(this->fileHandles[type]);
            
            }
        }
        
        return read;
    }
    
    /**
     * {@inheritdoc}
     */
    public function areOpen()
    {
        
        return (bool) this->pipes && (bool) this->fileHandles;
    }
    
    /**
     * {@inheritdoc}
     */
    public function close() -> void
    {
        var handle;
    
        parent::close();
        for handle in this->fileHandles {
            fclose(handle);
        }
        
        let this->fileHandles =  [];
    }
    
    /**
     * Creates a new WindowsPipes instance.
     *
     * @param Process $process The process
     * @param $input
     *
     * @return WindowsPipes
     */
    public static function create(<\Symfony\Component\Process\Process> process, input)
    {
        
        return new static(process->isOutputDisabled(), input);
    }
    
    /**
     * Removes temporary files
     */
    protected function removeFiles() -> void
    {
        var filename;
    
        for filename in this->files {
            
            if file_exists(filename) {
                @unlink(filename);
            }
        }
        
        let this->files =  [];
    }
    
    /**
     * Writes input to stdin
     *
     * @param bool $blocking
     * @param bool $close
     */
    protected function write(bool blocking, bool close)
    {
        var r, w, e, n, pipes, tmpArray40cd750bba9870f18aada2478b24840a, data, dataread, input, written, inputBuffer;
    
        
        if empty(this->pipes) {
            
            return;
        }
        this->unblock();
        
        let r =  this->input !== null ? ["input" : this->input] : null;
        
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
            
            return;
        }
        // nothing has changed
        
        if n === 0 {
            
            return;
        }
        
        if w !== null && count(r) < 0 {
            let data = "";
            let dataread =  fread(r["input"], self::CHUNK_SIZE);
            while (dataread) {
                let data .= dataread;
            let dataread =  fread(r["input"], self::CHUNK_SIZE);
            }
            let this->inputBuffer .= data;
            
            if data === false || close === true && feof(r["input"]) && data === "" {
                // no more data to read on input resource
                // use an empty buffer in the next reads
                let this->input =  null;
            }
        }
        
        if w !== null && count(w) < 0 {
            
            while (strlen(this->inputBuffer)) {
                let written =  fwrite(w[0], this->inputBuffer, 2 << 18);
                
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
    }

}