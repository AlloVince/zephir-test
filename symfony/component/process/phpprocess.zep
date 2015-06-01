/*
 * This file is part of the Symfony package.
 *
 * (c) Fabien Potencier <fabien@symfony.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
namespace Symfony\Component\Process;

use Symfony\Component\Process\Exception\RuntimeException;
/**
 * PhpProcess runs a PHP script in an independent process.
 *
 * $p = new PhpProcess('<?php echo "foo"; ?>');
 * $p->run();
 * print $p->getOutput()."\n";
 *
 * @author Fabien Potencier <fabien@symfony.com>
 *
 * @api
 */
class PhpProcess extends Process
{
    /**
     * Constructor.
     *
     * @param string $script  The PHP script to run (as a string)
     * @param string $cwd     The working directory
     * @param array  $env     The environment variables
     * @param int    $timeout The timeout in seconds
     * @param array  $options An array of options for proc_open
     *
     * @api
     */
    public function __construct(string script, string cwd = null, array env = [], int timeout = 60, array options = []) -> void
    {
        var executableFinder, php;
    
        let executableFinder =  new PhpExecutableFinder();
        let php =  executableFinder->find();
        if php === false {
            let php =  null;
        }
        parent::__construct(php, cwd, env, script, timeout, options);
    }
    
    /**
     * Sets the path to the PHP binary to use.
     *
     * @api
     */
    public function setPhpBinary(php) -> void
    {
        this->setCommandLine(php);
    }
    
    /**
     * {@inheritdoc}
     */
    public function start(callback = null) -> void
    {
        
        if this->getCommandLine() === null {
            throw new RuntimeException("Unable to find the PHP executable.");
        }
        parent::start(callback);
    }

}