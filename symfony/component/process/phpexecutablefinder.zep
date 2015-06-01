/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process;

/**
 * An executable finder specifically designed for the PHP executable.
 *
 * @author Fabien Potencier <fabien@symfony.com>
 * @author Johannes M. Schmitt <schmittjoh@gmail.com>
 */
class PhpExecutableFinder
{
    protected executableFinder;
    public function __construct() -> void
    {
        let this->executableFinder =  new ExecutableFinder();
    }
    
    /**
     * Finds The PHP executable.
     *
     * @param bool $includeArgs Whether or not include command arguments
     *
     * @return string|false The PHP executable path or false if it cannot be found
     */
    public function find(bool includeArgs = true)
    {
        var hhvm, tmpArray148a54a1b642f15706f8ba58ec4406c6, php, dirs;
    
        // HHVM support
        
        if defined("HHVM_VERSION") {
            let hhvm =  getenv("PHP_BINARY");
            return (
            hhvm !== false ? hhvm : PHP_BINARY) . (
            includeArgs ? implode(" ", this->findArguments()) . " " : "");
        }
        // PHP_BINARY return the current sapi executable
        let tmpArray148a54a1b642f15706f8ba58ec4406c6 = ["cli", "cli-server"];
        if defined("PHP_BINARY") && PHP_BINARY && in_array(PHP_SAPI, tmpArray148a54a1b642f15706f8ba58ec4406c6) && is_file(PHP_BINARY) {
            
            return PHP_BINARY;
        }
        let php =  getenv("PHP_PATH");
        if php {
            
            if !is_executable(php) {
                
                return false;
            }
            
            return php;
        }
        let php =  getenv("PHP_PEAR_PHP_BIN");
        if php {
            
            if is_executable(php) {
                
                return php;
            }
        }
        
        let dirs =  [PHP_BINDIR];
        
        if DIRECTORY_SEPARATOR === "\\" {
            let dirs[] = "C:\\xampp\\php\\";
        }
        
        return this->executableFinder->find("php", false, dirs);
    }
    
    /**
     * Finds the PHP executable arguments.
     *
     * @return array The PHP executable arguments
     */
    public function findArguments() -> array
    {
        var arguments;
    
        
        let arguments =  [];
        // HHVM support
        
        if defined("HHVM_VERSION") {
            let arguments[] = "--php";
        }
        
        return arguments;
    }

}