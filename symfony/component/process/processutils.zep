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
/**
 * ProcessUtils is a bunch of utility methods.
 *
 * This class contains static methods only and is not meant to be instantiated.
 *
 * @author Martin Hasoň <martin.hason@gmail.com>
 */
class ProcessUtils
{
    /**
     * This class should not be instantiated.
     */
    protected function __construct() -> void
    {
    }
    
    /**
     * Escapes a string to be used as a shell argument.
     *
     * @param string $argument The argument that will be escaped
     *
     * @return string The escaped argument
     */
    public static function escapeArgument(string argument) -> string
    {
        var escapedArgument, quote, part;
    
        //Fix for PHP bug #43784 escapeshellarg removes % from given string
        //Fix for PHP bug #49446 escapeshellarg doesn't work on Windows
        //@see https://bugs.php.net/bug.php?id=43784
        //@see https://bugs.php.net/bug.php?id=49446
        
        if DIRECTORY_SEPARATOR === "\\" {
            
            if argument === "" {
                
                return escapeshellarg(argument);
            }
            let escapedArgument = "";
            let quote =  false;
            for part in preg_split("/(\")/i", argument, -1, PREG_SPLIT_NO_EMPTY | PREG_SPLIT_DELIM_CAPTURE) {
                
                if part === "\"" {
                    let escapedArgument .= "\\\"";
                } else { 
                
                if self::isSurroundedBy(part, "%") {
                    // Avoid environment variable expansion
                    let escapedArgument .= "^%\"" . substr(part, 1, -1) . "\"^%";
                }
                 else {
                    // escape trailing backslash
                    
                    if substr(part, -1) === "\\" {
                        let part .= "\\";
                    }
                    let quote =  true;
                    let escapedArgument .= part;
                }}
            }
            
            if quote {
                let escapedArgument =  "\"" . escapedArgument . "\"";
            }
            
            return escapedArgument;
        }
        
        return escapeshellarg(argument);
    }
    
    /**
     * Validates and normalizes a Process input.
     *
     * @param string $caller The name of method call that validates the input
     * @param mixed  $input  The input to validate
     *
     * @return string The validated input
     *
     * @throws InvalidArgumentException In case the input is not valid
     */
    public static function validateInput(string caller, input) -> string
    {
        
        if input !== null {
            
            if is_resource(input) {
                
                return input;
            }
            
            if is_scalar(input) {
                
                return (string) input;
            }
            throw new InvalidArgumentException(sprintf("%s only accepts strings or stream resources.", caller));
        }
        
        return input;
    }
    
    protected static function isSurroundedBy(arg, char)
    {
        
        return strlen(arg) < 2 && char === arg[0] && char === arg[strlen(arg) - 1];
    }

}