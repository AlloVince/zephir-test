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
 * Generic executable finder.
 *
 * @author Fabien Potencier <fabien@symfony.com>
 * @author Johannes M. Schmitt <schmittjoh@gmail.com>
 */
class ExecutableFinder
{
    protected suffixes = [".exe", ".bat", ".cmd", ".com"];
    /**
     * Replaces default suffixes of executable.
     *
     * @param array $suffixes
     */
    public function setSuffixes(array suffixes) -> void
    {
        let this->suffixes = suffixes;
    }
    
    /**
     * Adds new possible suffix to check for executable.
     *
     * @param string $suffix
     */
    public function addSuffix(string suffix) -> void
    {
        let this->suffixes[] = suffix;
    }
    
    /**
     * Finds an executable by name.
     *
     * @param string $name      The executable name (without the extension)
     * @param string $default   The default to return if no executable is found
     * @param array  $extraDirs Additional dirs to check into
     *
     * @return string The executable path or default value
     */
    public function find(string name, string defaultStr = null, array extraDirs = []) -> string
    {
        var searchPath, dirs, tmpArray40cd750bba9870f18aada2478b24840a, path, suffixes, pathExt, suffix, dir, file;
    
        
        if ini_get("open_basedir") {
            let searchPath =  explode(PATH_SEPARATOR, ini_get("open_basedir"));
            
            let dirs =  [];
            for path in searchPath {
                
                if is_dir(path) {
                    let dirs[] = path;
                } else {
                    
                    if basename(path) == name && is_executable(path) {
                        
                        return path;
                    }
                }
            }
        } else {
            let dirs =  array_merge(explode(PATH_SEPARATOR,
            getenv("PATH") ? explode(PATH_SEPARATOR, getenv("PATH")) : getenv("Path")), extraDirs);
        }
        
        let suffixes =  [""];
        
        if DIRECTORY_SEPARATOR === "\\" {
            let pathExt =  getenv("PATHEXT");
            
            let suffixes =  pathExt ? explode(PATH_SEPARATOR, pathExt) : this->suffixes;
        }
        for suffix in suffixes {
            for dir in dirs {
                let file =  dir . DIRECTORY_SEPARATOR . name;
                if is_file(file) && (DIRECTORY_SEPARATOR === "\\" || is_executable(file)) {
                    
                    return file;
                }
            }
        }
        
        return defaultStr;
    }

}
