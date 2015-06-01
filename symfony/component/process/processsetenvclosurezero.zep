namespace Symfony\Component\Process;

class ProcesssetEnvClosureZero
{

    public function __construct()
    {
        
    }

    public function __invoke(value)
    {
    
    return !is_array(value);
    }
}
    