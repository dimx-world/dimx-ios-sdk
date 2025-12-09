#pragma once

#ifndef DIMX_CORE_EVENT_SUBSCRIBER_H
#define DIMX_CORE_EVENT_SUBSCRIBER_H

#include <Common.h>
#include <EventPublisher.h>

class EventSubscriber
{
public:
    EventSubscriber() = default;

    ~EventSubscriber() {
        for(const auto& wkPub: mPublishers) {
            if (auto shPub = wkPub.lock()) {
                shPub->unsubscribe(this);
            }
        }
    }

    template <typename... Args, typename Event, typename Func>
    void add(EventPublisher<Event>& publisher, Event event, Func func) {
        auto shPub = publisher.shared_from_this();
        ASSERT(shPub, "Invalid publisher");
        mPublishers.emplace_back(shPub);
        publisher.template subscribe<Args...>(event, this, std::move(func));
    }

private:
    std::vector<std::weak_ptr<BaseEventPublisher>> mPublishers;
};

#endif // DIMX_CORE_EVENT_SUBSCRIBER_H