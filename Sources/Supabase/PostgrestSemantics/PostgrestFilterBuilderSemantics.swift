import PostgREST

extension PostgrestFilterBuilder {
    public func equals(column: String, value: String) -> PostgrestFilterBuilder {
        eq(column: column, value: value)
    }
    
    public func notEquals(column: String, value: String) -> PostgrestFilterBuilder {
        neq(column: column, value: value)
    }
    
    public func greaterThan(column: String, value: String) -> PostgrestFilterBuilder {
        gt(column: column, value: value)
    }
    
    public func greaterThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
        gte(column: column, value: value)
    }
    
    public func lowerThan(column: String, value: String) -> PostgrestFilterBuilder {
        lt(column: column, value: value)
    }
    
    public func lowerThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
        lte(column: column, value: value)
    }
    
    public func rangeLowerThan(column: String, range: String) -> PostgrestFilterBuilder {
        rangeLt(column: column, range: range)
    }
    
    public func rangeGreaterThan(column: String, value: String) -> PostgrestFilterBuilder {
        rangeGt(column: column, range: value)
    }
    
    public func rangeGreaterThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
        rangeGte(column: column, range: value)
    }
    
    public func rangeLowerThanOrEquals(column: String, value: String) -> PostgrestFilterBuilder {
        rangeLte(column: column, range: value)
    }
    
    public func fullTextSearch(column: String, query: String, config: String? = nil) -> PostgrestFilterBuilder {
        fts(column: column, query: query, config: config)
    }
    
    public func plaintoFullTextSearch(column: String, query: String, config: String? = nil) -> PostgrestFilterBuilder {
        plfts(column: column, query: query, config: config)
    }
    
    public func phrasetoFullTextSearch(column: String, query: String, config: String? = nil) -> PostgrestFilterBuilder {
        phfts(column: column, query: query, config: config)
    }
    
    public func webFullTextSearch(column: String, query: String, config: String? = nil) -> PostgrestFilterBuilder {
        wfts(column: column, query: query, config: config)
    }
}
