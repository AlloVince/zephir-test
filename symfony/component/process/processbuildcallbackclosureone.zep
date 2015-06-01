namespace Symfony\Component\Process;

class ProcessbuildCallbackClosureOne
{
    private callback;
    private out;

    public function __construct(callback, out)
    {
                let this->callback = callback;
        let this->out = out;

    }

    public function __invoke(type, data)
    {
    
    if this->out == type {
        this->addOutput(data);
    } else {
        this->addErrorOutput(data);
    }
    
    if this->callback !== null {
        call_user_func(this->callback, type, data);
    }
    }
}
    