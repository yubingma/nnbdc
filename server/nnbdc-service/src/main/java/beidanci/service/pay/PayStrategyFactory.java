package beidanci.service.pay;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import beidanci.api.model.PaymentChannel;

@Component
public class PayStrategyFactory {

    private final Map<PaymentChannel, PayStrategy> strategyMap = new HashMap<>();

    @Autowired
    public PayStrategyFactory(List<PayStrategy> strategies) {
        for (PayStrategy strategy : strategies) {
            strategyMap.put(strategy.getChannel(), strategy);
        }
    }

    public PayStrategy getStrategy(PaymentChannel channel) {
        PayStrategy strategy = strategyMap.get(channel);
        if (strategy == null) {
            throw new IllegalArgumentException("Unsupported payment channel: " + channel);
        }
        return strategy;
    }
}
