/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process\Exception;

use Symfony\Component\Process\Process;
/**
 * Exception for failed processes.
 *
 * @author Johannes M. Schmitt <schmittjoh@gmail.com>
 */
class ProcessFailedException extends RuntimeException
{
    protected process;
    public function __construct(<\Symfony\Component\Process\Process> process) -> void
    {
        var error;
    
        
        if process->isSuccessful() {
            throw new InvalidArgumentException("Expected a failed process, but the given process was successful.");
        }
        let error =  sprintf("The command \"%s\" failed." . "
Exit Code: %s(%s)", process->getCommandLine(), process->getExitCode(), process->getExitCodeText());
        
        if !process->isOutputDisabled() {
            let error .= sprintf("

Output:
================
%s

Error Output:
================
%s", process->getOutput(), process->getErrorOutput());
        }
        parent::__construct(error);
        let this->process = process;
    }
    
    public function getProcess()
    {
        
        return this->process;
    }

}