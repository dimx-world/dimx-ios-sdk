#pragma once

class CoreObjectComponentFactory
{
public:
    static CoreObjectComponentFactory& instance() {
        static CoreObjectComponentFactory factory;
        return factory;
    }

};
