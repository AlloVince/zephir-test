/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process\Pipes;

/**
 * @author Romain Neutron <imprec@gmail.com>
 *
 * @internal
 */
abstract class AbstractPipes implements PipesInterface
{
    /** @var array */
    public pipes = [];
    /** @var string */
    protected inputBuffer = "";
    /** @var resource|null */
    protected input;
    /** @var bool */
    protected blocked = true;
    /**
     * {@inheritdoc}
     */
    public function close() -> void
    {
        var pipe;
    
        for pipe in this->pipes {
            fclose(pipe);
        }
        
        let this->pipes =  [];
    }
    
    /**
     * Returns true if a system call has been interrupted.
     *
     * @return bool
     */
    protected function hasSystemCallBeenInterrupted() -> bool
    {
        var lastError;
    
        let lastError =  error_get_last();
        // stream_select returns false when the `select` system call is interrupted by an incoming signal
        
        return isset lastError["message"] && stripos(lastError["message"], "interrupted system call") !== false;
    }
    
    /**
     * Unblocks streams
     */
    protected function unblock()
    {
        var pipe;
    
        
        if !this->blocked {
            
            return;
        }
        for pipe in this->pipes {
            stream_set_blocking(pipe, 0);
        }
        
        if this->input !== null {
            stream_set_blocking(this->input, 0);
        }
        let this->blocked =  false;
    }

}