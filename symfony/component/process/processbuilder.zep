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
/**
 * Process builder.
 *
 * @author Kris Wallsmith <kris@symfony.com>
 */
class ProcessBuilder
{
    protected arguments;
    protected cwd;
    protected env = [];
    protected input;
    protected timeout = 60;
    protected options = [];
    protected inheritEnv = true;
    protected prefix = [];
    protected outputDisabled = false;
    /**
     * Constructor.
     *
     * @param string[] $arguments An array of arguments
     */
    public function __construct(array arguments = []) -> void
    {
        let this->arguments = arguments;
    }
    
    /**
     * Creates a process builder instance.
     *
     * @param string[] $arguments An array of arguments
     *
     * @return ProcessBuilder
     */
    public static function create(array arguments = [])
    {
        
        return new static(arguments);
    }
    
    /**
     * Adds an unescaped argument to the command string.
     *
     * @param string $argument A command argument
     *
     * @return ProcessBuilder
     */
    public function add(string argument)
    {
        let this->arguments[] = argument;
        
        return this;
    }
    
    /**
     * Adds a prefix to the command string.
     *
     * The prefix is preserved when resetting arguments.
     *
     * @param string|array $prefix A command prefix or an array of command prefixes
     *
     * @return ProcessBuilder
     */
    public function setPrefix(prefix)
    {
        
        let this->prefix =  is_array(prefix) ? prefix : [prefix];
        
        return this;
    }
    
    /**
     * Sets the arguments of the process.
     *
     * Arguments must not be escaped.
     * Previous arguments are removed.
     *
     * @param string[] $arguments
     *
     * @return ProcessBuilder
     */
    public function setArguments(array arguments)
    {
        let this->arguments = arguments;
        
        return this;
    }
    
    /**
     * Sets the working directory.
     *
     * @param null|string $cwd The working directory
     *
     * @return ProcessBuilder
     */
    public function setWorkingDirectory(cwd)
    {
        let this->cwd = cwd;
        
        return this;
    }
    
    /**
     * Sets whether environment variables will be inherited or not.
     *
     * @param bool $inheritEnv
     *
     * @return ProcessBuilder
     */
    public function inheritEnvironmentVariables(bool inheritEnv = true)
    {
        let this->inheritEnv = inheritEnv;
        
        return this;
    }
    
    /**
     * Sets an environment variable.
     *
     * Setting a variable overrides its previous value. Use `null` to unset a
     * defined environment variable.
     *
     * @param string      $name  The variable name
     * @param null|string $value The variable value
     *
     * @return ProcessBuilder
     */
    public function setEnv(string name, value)
    {
        let this->env[name] = value;
        
        return this;
    }
    
    /**
     * Adds a set of environment variables.
     *
     * Already existing environment variables with the same name will be
     * overridden by the new values passed to this method. Pass `null` to unset
     * a variable.
     *
     * @param array $variables The variables
     *
     * @return ProcessBuilder
     */
    public function addEnvironmentVariables(array variables)
    {
        let this->env =  array_replace(this->env, variables);
        
        return this;
    }
    
    /**
     * Sets the input of the process.
     *
     * @param mixed $input The input as a string
     *
     * @return ProcessBuilder
     *
     * @throws InvalidArgumentException In case the argument is invalid
     */
    public function setInput(input)
    {
        let this->input =  ProcessUtils::validateInput(sprintf("%s::%s", __CLASS__, __FUNCTION__), input);
        
        return this;
    }
    
    /**
     * Sets the process timeout.
     *
     * To disable the timeout, set this value to null.
     *
     * @param float|null $timeout
     *
     * @return ProcessBuilder
     *
     * @throws InvalidArgumentException
     */
    public function setTimeout(timeout)
    {
        
        if timeout === null {
            let this->timeout =  null;
            
            return this;
        }
        let timeout =  (double) timeout;
        
        if timeout < 0 {
            throw new InvalidArgumentException("The timeout value must be a valid positive integer or float number.");
        }
        let this->timeout = timeout;
        
        return this;
    }
    
    /**
     * Adds a proc_open option.
     *
     * @param string $name  The option name
     * @param string $value The option value
     *
     * @return ProcessBuilder
     */
    public function setOption(string name, string value)
    {
        let this->options[name] = value;
        
        return this;
    }
    
    /**
     * Disables fetching output and error output from the underlying process.
     *
     * @return ProcessBuilder
     */
    public function disableOutput()
    {
        let this->outputDisabled =  true;
        
        return this;
    }
    
    /**
     * Enables fetching output and error output from the underlying process.
     *
     * @return ProcessBuilder
     */
    public function enableOutput()
    {
        let this->outputDisabled =  false;
        
        return this;
    }
    
    /**
     * Creates a Process instance and returns it.
     *
     * @return Process
     *
     * @throws LogicException In case no arguments have been provided
     */
    public function getProcess()
    {
        var options, arguments, script, env, process;
    
        
        if count(this->prefix) === 0 && count(this->arguments) === 0 {
            throw new LogicException("You must add() command arguments before calling getProcess().");
        }
        let options =  this->options;
        let arguments =  array_merge(this->prefix, this->arguments);
        let script =  implode(" ", array_map(["\\ProcessUtils" . __NAMESPACE__, "escapeArgument"], arguments));
        
        if this->inheritEnv {
            // include $_ENV for BC purposes
            let env =  array_replace(_ENV, _SERVER, this->env);
        } else {
            let env =  this->env;
        }
        let process =  new Process(script, this->cwd, env, this->input, this->timeout, options);
        
        if this->outputDisabled {
            process->disableOutput();
        }
        
        return process;
    }

}